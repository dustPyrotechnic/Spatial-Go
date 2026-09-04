import Foundation

/// 一方提交的完整死棋提案。
///
/// 这是私有数据：在双方都提交之前，它绝不能出现在公共状态、公共事件或任何展示表面上。
nonisolated struct DeadGroupProposal: Hashable, Sendable {
    /// 提交所属的审核轮次。
    let reviewID: ReviewID
    /// 已校验、去重并按 ``GroupID`` 规范排序的棋块集合。
    let groups: [GroupID]
}

/// 私有权威对局状态。
///
/// 它同时持有规则状态和尚未公开的死棋提案；只有 ``publicState`` 是可以交给
/// UI、玩家和 AR 层的投影。
nonisolated struct AuthoritativeGameState: Hashable, Sendable {
    /// 规则状态：棋盘、轮次、阶段、提子数、修订号、超级劫历史与权威日志。
    private(set) var state: GameState
    /// 各方的私有死棋提案。
    private(set) var deadGroupProposals: [Stone: DeadGroupProposal]

    init(configuration: GameConfiguration, digester: any StateKeyDigesting = StateKeyDigestV1()) {
        self.state = GameState(configuration: configuration, digester: digester)
        self.deadGroupProposals = [:]
    }

    init(state: GameState, deadGroupProposals: [Stone: DeadGroupProposal] = [:]) {
        self.state = state
        self.deadGroupProposals = deadGroupProposals
    }

    /// 公共投影。第二份提交完成前只暴露"已提交/未提交"。
    var publicState: PublicGameState {
        let bothSubmitted =
            deadGroupProposals[.black] != nil && deadGroupProposals[.white] != nil
        var status = [Stone: DeadGroupSubmissionStatus]()
        for color in Stone.allCases {
            guard let proposal = deadGroupProposals[color] else {
                status[color] = .notSubmitted
                continue
            }
            status[color] = bothSubmitted ? .revealed(proposal.groups) : .submitted
        }
        return PublicGameState(
            board: state.board,
            nextPlayer: state.nextPlayer,
            phase: state.phase,
            consecutivePasses: state.consecutivePasses,
            capturedByBlack: state.capturedByBlack,
            capturedByWhite: state.capturedByWhite,
            revision: state.revision,
            reviewID: state.currentReviewID,
            result: state.result,
            submissionStatus: status
        )
    }

    // MARK: - 原子提交

    mutating func commitPlacement(
        board: Board,
        capturedCount: Int,
        actor: Stone,
        stateKey: StateKey,
        digest: UInt64,
        action: GameAction
    ) throws {
        try state.commitPlacement(
            board: board,
            capturedCount: capturedCount,
            actor: actor,
            stateKey: stateKey,
            digest: digest,
            action: action
        )
    }

    /// 提交一次停着。
    ///
    /// - Returns: 本次停着是否使棋局进入计分审核。
    mutating func commitPass(
        actor: Stone,
        stateKey: StateKey,
        digest: UInt64,
        action: GameAction
    ) throws -> Bool {
        try state.commitPass(actor: actor, stateKey: stateKey, digest: digest, action: action)
    }

    mutating func commitResign(actor: Stone, action: GameAction) throws {
        try state.commitResign(actor: actor, action: action)
    }

    /// 记录一份死棋提案，并在双方一致时原子完成移除、计分与终局。
    mutating func commitReviewSubmission(
        proposal: DeadGroupProposal,
        actor: Stone,
        action: GameAction,
        finalBoard: Board?,
        result: GameResult?
    ) throws {
        try state.commitReviewSubmission(action: action, finalBoard: finalBoard, result: result)
        deadGroupProposals[actor] = proposal
    }

    /// 恢复对局：清零连续停着数并丢弃两份提案，从不公开它们。
    mutating func commitResume(action: GameAction) throws {
        try state.commitResume(action: action)
        deadGroupProposals.removeAll()
    }
}
