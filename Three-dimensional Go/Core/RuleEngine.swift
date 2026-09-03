import Foundation

/// 规则核心拒绝一个动作时给出的稳定错误值。
nonisolated enum RuleViolation: Error, Equatable, Sendable {
    case wrongPhase, wrongPlayer, outOfBounds, occupied
    case suicide, superko, arithmeticOverflow
}

/// `3d-go/1` 规则引擎。
///
/// 所有动作都按“复制—校验—提交”执行：任何被拒绝的动作都不会修改棋盘、轮次、
/// 提子数、修订号或历史。
nonisolated struct RuleEngine: Sendable {
    /// 当前权威规则状态。
    private(set) var state: GameState
    /// 计算超级劫摘要使用的实现。
    private let digester: any StateKeyDigesting

    init(
        configuration: GameConfiguration,
        digester: any StateKeyDigesting = StateKeyDigestV1()
    ) {
        self.state = GameState(configuration: configuration, digester: digester)
        self.digester = digester
    }

    init(state: GameState, digester: any StateKeyDigesting = StateKeyDigestV1()) {
        self.state = state
        self.digester = digester
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
    /// - Returns: 已接受动作产生的状态增量。
    /// - Throws: 校验失败时抛出 ``RuleViolation``，且状态保持不变。
    @discardableResult
    mutating func apply(_ action: GameAction) throws -> GameTransition {
        switch action {
        case let .place(actor, position):
            return try applyPlacement(actor: actor, position: position, action: action)
        }
    }

    private mutating func applyPlacement(
        actor: Stone,
        position: GridPosition,
        action: GameAction
    ) throws -> GameTransition {
        guard state.phase == .playing else { throw RuleViolation.wrongPhase }
        guard actor == state.nextPlayer else { throw RuleViolation.wrongPlayer }
        guard state.board.contains(position) else { throw RuleViolation.outOfBounds }
        guard state.board[position] == nil else { throw RuleViolation.occupied }

        var candidate = state.board
        candidate[position] = actor

        let capturedPositions = RuleEngine.capturedPositions(
            on: &candidate,
            around: position,
            capturing: actor.opponent
        )

        guard let own = candidate.groupAndLiberties(at: position), !own.liberties.isEmpty else {
            throw RuleViolation.suicide
        }

        let key = StateKey(board: candidate, nextPlayer: actor.opponent)
        let digest = digester.digest(key)
        guard !state.superkoSeen.contains(key, digest: digest) else {
            throw RuleViolation.superko
        }

        var committed = state
        try committed.commitPlacement(
            board: candidate,
            capturedCount: capturedPositions.count,
            actor: actor,
            stateKey: key,
            digest: digest,
            action: action
        )
        state = committed

        return GameTransition(
            action: action,
            revision: state.revision,
            placedStone: PlacedStone(position: position, stone: actor),
            capturedPositions: capturedPositions,
            nextPlayer: state.nextPlayer
        )
    }

    /// 在同一临时快照上找出并移除全部零气敌块。
    ///
    /// 先按棋块锚点去重收集与落点相邻的敌块，再统一移除，因此多个棋块同时被提。
    ///
    /// - Parameters:
    ///   - board: 已经临时落子的候选棋盘，方法就地移除被提棋子。
    ///   - position: 本次落点。
    ///   - color: 被提方颜色。
    /// - Returns: 被提走的坐标，按棋盘规范 z/y/x 顺序排列。
    private static func capturedPositions(
        on board: inout Board,
        around position: GridPosition,
        capturing color: Stone
    ) -> [GridPosition] {
        var anchors = Set<GridPosition>()
        var doomed = [GridPosition]()
        for neighbor in board.neighbors(of: position) where board[neighbor] == color {
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
}
