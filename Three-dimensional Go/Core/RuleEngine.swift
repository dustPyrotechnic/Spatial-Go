import Foundation

/// 规则核心拒绝一个动作时给出的稳定错误值。
nonisolated enum RuleViolation: Error, Equatable, Sendable {
    case wrongPhase, wrongPlayer, outOfBounds, occupied
    case suicide, superko, arithmeticOverflow
    /// 该方在本轮审核中已经提交过死棋提案。
    case alreadySubmitted(Stone)
    /// 提案携带的审核轮次不是当前活动轮次。
    case staleReviewID(ReviewID)
    /// 提案中的棋块标识与审核棋盘上的实际棋块不符。
    case invalidDeadGroup(GroupID)
}

/// `3d-go/1` 规则引擎。
///
/// 所有动作都按“复制—校验—提交”执行：候选状态在私有副本上构造，任何被拒绝的动作
/// 都不会修改棋盘、轮次、提子数、修订号、超级劫历史、权威日志或死棋提案。
nonisolated struct RuleEngine: Sendable {
    /// 私有权威状态。
    private(set) var authoritative: AuthoritativeGameState
    /// 计算超级劫摘要使用的实现。
    private let digester: any StateKeyDigesting
    /// 计算棋盘摘要使用的实现。
    private let boardDigester: any BoardDigesting

    /// 当前规则状态。
    var state: GameState { authoritative.state }
    /// 当前公共状态投影。
    var publicState: PublicGameState { authoritative.publicState }
    /// 当前渲染层快照。
    var snapshot: GameSnapshot { authoritative.makeSnapshot(digester: boardDigester) }

    init(
        configuration: GameConfiguration,
        digester: any StateKeyDigesting = StateKeyDigestV1(),
        boardDigester: any BoardDigesting = BoardDigestV1()
    ) {
        self.authoritative = AuthoritativeGameState(
            configuration: configuration, digester: digester)
        self.digester = digester
        self.boardDigester = boardDigester
    }

    init(
        state: GameState,
        digester: any StateKeyDigesting = StateKeyDigestV1(),
        boardDigester: any BoardDigesting = BoardDigestV1()
    ) {
        self.authoritative = AuthoritativeGameState(state: state)
        self.digester = digester
        self.boardDigester = boardDigester
    }

    init(
        authoritative: AuthoritativeGameState,
        digester: any StateKeyDigesting = StateKeyDigestV1(),
        boardDigester: any BoardDigesting = BoardDigestV1()
    ) {
        self.authoritative = authoritative
        self.digester = digester
        self.boardDigester = boardDigester
    }

    /// 由权威日志确定性重放一局棋。
    ///
    /// - Parameters:
    ///   - log: 待重放的权威日志。
    ///   - digester: 计算超级劫摘要使用的实现。
    /// - Returns: 重放到日志末尾的规则引擎。
    /// - Throws: 日志中出现不能被规则接受的动作时抛出 ``RuleViolation``。
    static func replaying(
        _ log: GameLog,
        digester: any StateKeyDigesting = StateKeyDigestV1()
    ) throws -> RuleEngine {
        var engine = RuleEngine(configuration: log.header.configuration, digester: digester)
        for entry in log.entries {
            try engine.apply(entry.action)
        }
        return engine
    }

    /// 应用一个动作。
    ///
    /// - Parameter action: 请求的动作。
    /// - Returns: 已接受动作产生的状态增量与公共事件。
    /// - Throws: 校验失败时抛出 ``RuleViolation``，且全部状态保持不变。
    @discardableResult
    mutating func apply(_ action: GameAction) throws -> GameTransition {
        var candidate = authoritative
        let transition: GameTransition
        switch action {
        case let .place(actor, position):
            transition = try applyPlacement(
                to: &candidate, actor: actor, position: position, action: action)
        case let .pass(actor):
            transition = try applyPass(to: &candidate, actor: actor, action: action)
        case let .resign(actor):
            transition = try applyResignation(to: &candidate, actor: actor, action: action)
        case let .submitDeadGroups(actor, groups):
            transition = try applySubmission(
                to: &candidate, actor: actor, groups: groups, action: action)
        case let .resume(actor):
            transition = try applyResume(to: &candidate, actor: actor, action: action)
        }
        authoritative = candidate
        return transition
    }

    // MARK: - 落子

    private func applyPlacement(
        to candidate: inout AuthoritativeGameState,
        actor: Stone,
        position: GridPosition,
        action: GameAction
    ) throws -> GameTransition {
        guard candidate.state.phase == .playing else { throw RuleViolation.wrongPhase }
        guard actor == candidate.state.nextPlayer else { throw RuleViolation.wrongPlayer }
        guard candidate.state.board.contains(position) else { throw RuleViolation.outOfBounds }
        guard candidate.state.board[position] == nil else { throw RuleViolation.occupied }

        var board = candidate.state.board
        board[position] = actor

        let capturedPositions = RuleEngine.capturedPositions(
            on: &board,
            around: position,
            capturedColor: actor.opponent
        )

        guard let own = board.groupAndLiberties(at: position), !own.liberties.isEmpty else {
            throw RuleViolation.suicide
        }

        let key = StateKey(board: board, nextPlayer: actor.opponent)
        let digest = digester.digest(key)
        guard !candidate.state.superkoSeen.contains(key, digest: digest) else {
            throw RuleViolation.superko
        }

        try candidate.commitPlacement(
            board: board,
            capturedCount: capturedPositions.count,
            actor: actor,
            stateKey: key,
            digest: digest,
            action: action
        )

        let revision = candidate.state.revision
        return GameTransition(
            action: action,
            revision: revision,
            placedStone: PlacedStone(position: position, stone: actor),
            capturedPositions: capturedPositions,
            nextPlayer: candidate.state.nextPlayer,
            events: [
                .placed(
                    actor: actor, position: position, captured: capturedPositions,
                    revision: revision)
            ],
            boardDeltas: capturedPositions.map { BoardDelta(position: $0, stone: nil) }
                + [BoardDelta(position: position, stone: actor)]
        )
    }

    /// 在同一临时快照上找出并移除全部零气敌块。
    ///
    /// 先按棋块锚点去重收集与落点相邻的敌块，再统一移除，因此多个棋块同时被提。
    ///
    /// - Parameters:
    ///   - board: 已经临时落子的候选棋盘，方法就地移除被提棋子。
    ///   - position: 本次落点。
    ///   - capturedColor: 被提方颜色。
    /// - Returns: 被提走的坐标，按棋盘规范 z/y/x 顺序排列。
    private static func capturedPositions(
        on board: inout Board,
        around position: GridPosition,
        capturedColor: Stone
    ) -> [GridPosition] {
        var anchors = Set<GridPosition>()
        var doomed = [GridPosition]()
        for neighbor in board.neighbors(of: position) where board[neighbor] == capturedColor {
            guard let group = board.groupAndLiberties(at: neighbor) else { continue }
            guard let anchor = group.stones.min(), anchors.insert(anchor).inserted else { continue }
            guard group.liberties.isEmpty else { continue }
            doomed.append(contentsOf: group.stones)
        }
        for stone in doomed {
            board[stone] = nil
        }
        return doomed.sorted { board.linearIndex(of: $0) < board.linearIndex(of: $1) }
    }

    // MARK: - 停着

    private func applyPass(
        to candidate: inout AuthoritativeGameState,
        actor: Stone,
        action: GameAction
    ) throws -> GameTransition {
        guard candidate.state.phase == .playing else { throw RuleViolation.wrongPhase }
        guard actor == candidate.state.nextPlayer else { throw RuleViolation.wrongPlayer }

        // 停着豁免提交前的超级劫重复拒绝，但接受后仍写入完整状态键。
        let key = StateKey(board: candidate.state.board, nextPlayer: actor.opponent)
        let digest = digester.digest(key)
        let enteredReview = try candidate.commitPass(
            actor: actor, stateKey: key, digest: digest, action: action)

        let revision = candidate.state.revision
        var events: [PublicGameEvent] = [
            .passed(
                actor: actor, consecutivePasses: candidate.state.consecutivePasses,
                revision: revision)
        ]
        if enteredReview, let reviewID = candidate.state.currentReviewID {
            events.append(.enteredScoringReview(reviewID: reviewID, revision: revision))
        }
        return GameTransition(
            action: action,
            revision: revision,
            placedStone: nil,
            capturedPositions: [],
            nextPlayer: candidate.state.nextPlayer,
            events: events,
            boardDeltas: []
        )
    }

    // MARK: - 认输

    private func applyResignation(
        to candidate: inout AuthoritativeGameState,
        actor: Stone,
        action: GameAction
    ) throws -> GameTransition {
        guard candidate.state.phase == .playing else { throw RuleViolation.wrongPhase }
        guard actor == candidate.state.nextPlayer else { throw RuleViolation.wrongPlayer }

        try candidate.commitResign(actor: actor, action: action)

        let revision = candidate.state.revision
        var events: [PublicGameEvent] = [.resigned(actor: actor, revision: revision)]
        if let result = candidate.state.result {
            events.append(.finished(result: result, revision: revision))
        }
        return GameTransition(
            action: action,
            revision: revision,
            placedStone: nil,
            capturedPositions: [],
            nextPlayer: candidate.state.nextPlayer,
            events: events,
            boardDeltas: []
        )
    }

    // MARK: - 死棋提案

    private func applySubmission(
        to candidate: inout AuthoritativeGameState,
        actor: Stone,
        groups: [GroupID],
        action: GameAction
    ) throws -> GameTransition {
        guard candidate.state.phase == .scoringReview,
            let reviewID = candidate.state.currentReviewID
        else { throw RuleViolation.wrongPhase }
        guard candidate.deadGroupProposals[actor] == nil else {
            throw RuleViolation.alreadySubmitted(actor)
        }

        // 审核期间棋盘不变，因此当前棋盘就是本轮固定的审核快照。
        let board = candidate.state.board
        for group in groups {
            guard group.reviewID == reviewID else {
                throw RuleViolation.staleReviewID(group.reviewID)
            }
            guard board.contains(group.anchor), board[group.anchor] == group.color,
                let stones = board.groupAndLiberties(at: group.anchor)?.stones,
                stones.min() == group.anchor
            else { throw RuleViolation.invalidDeadGroup(group) }
        }

        let normalized = Array(Set(groups)).sorted()
        let proposal = DeadGroupProposal(reviewID: reviewID, groups: normalized)
        let normalizedAction = GameAction.submitDeadGroups(actor: actor, groups: normalized)

        let opponentProposal = candidate.deadGroupProposals[actor.opponent]
        var finalBoard: Board?
        var result: GameResult?
        var removedPositions = [GridPosition]()
        if let opponentProposal, opponentProposal.groups == normalized {
            var scored = board
            var deadPositions = Set<GridPosition>()
            for group in normalized {
                guard let stones = scored.groupAndLiberties(at: group.anchor)?.stones else {
                    continue
                }
                deadPositions.formUnion(stones)
            }
            for position in deadPositions {
                scored[position] = nil
            }
            removedPositions = deadPositions.sorted {
                scored.linearIndex(of: $0) < scored.linearIndex(of: $1)
            }
            let breakdown = TerritoryScorer.score(
                board: board,
                removingDeadStones: deadPositions,
                komiHalfPoints: candidate.state.configuration.komiHalfPoints
            )
            finalBoard = scored
            result = .areaScore(
                AgreedScoreOutcome(
                    breakdown: breakdown, reviewID: reviewID, agreedDeadGroups: normalized))
        }

        try candidate.commitReviewSubmission(
            proposal: proposal,
            actor: actor,
            action: normalizedAction,
            finalBoard: finalBoard,
            result: result
        )

        let revision = candidate.state.revision
        var events: [PublicGameEvent] = [.deadGroupsSubmitted(actor: actor, revision: revision)]
        if let opponentProposal {
            let black = actor == .black ? normalized : opponentProposal.groups
            let white = actor == .white ? normalized : opponentProposal.groups
            events.append(
                .deadGroupsRevealed(
                    black: black, white: white, agreed: black == white, revision: revision))
        }
        if let result {
            events.append(.finished(result: result, revision: revision))
        }
        return GameTransition(
            action: normalizedAction,
            revision: revision,
            placedStone: nil,
            capturedPositions: [],
            nextPlayer: candidate.state.nextPlayer,
            events: events,
            boardDeltas: removedPositions.map { BoardDelta(position: $0, stone: nil) }
        )
    }

    // MARK: - 恢复对局

    private func applyResume(
        to candidate: inout AuthoritativeGameState,
        actor: Stone,
        action: GameAction
    ) throws -> GameTransition {
        guard candidate.state.phase == .scoringReview else { throw RuleViolation.wrongPhase }

        try candidate.commitResume(action: action)

        let revision = candidate.state.revision
        return GameTransition(
            action: action,
            revision: revision,
            placedStone: nil,
            capturedPositions: [],
            nextPlayer: candidate.state.nextPlayer,
            events: [
                .resumed(
                    actor: actor, nextPlayer: candidate.state.nextPlayer, revision: revision)
            ],
            boardDeltas: []
        )
    }
}
