import Foundation

/// 一轮计分审核的编号。
///
/// 初始为 0；每次第二个连续 `Pass` 成功提交时对 `reviewIndex` 做 checked `+1`，
/// 新值就是该轮的 `ReviewID`。恢复对局不递增。
nonisolated struct ReviewID: Hashable, Comparable, Codable, Sendable {
    let value: UInt32

    init(value: UInt32) {
        self.value = value
    }

    static func < (lhs: ReviewID, rhs: ReviewID) -> Bool { lhs.value < rhs.value }
}

/// 死棋提案中的棋块标识。
///
/// `anchor` 必须是棋块内按 x、再 y、再 z 比较得到的字典序最小实际坐标，
/// 这与棋盘序列化使用的 z/y/x 顺序是两套独立顺序。
nonisolated struct GroupID: Hashable, Comparable, Codable, Sendable {
    let reviewID: ReviewID
    let color: Stone
    let anchor: GridPosition

    init(reviewID: ReviewID, color: Stone, anchor: GridPosition) {
        self.reviewID = reviewID
        self.color = color
        self.anchor = anchor
    }

    /// 规范排序：先按审核轮次，再按颜色，最后按锚点字典序。
    static func < (lhs: GroupID, rhs: GroupID) -> Bool {
        if lhs.reviewID != rhs.reviewID { return lhs.reviewID < rhs.reviewID }
        if lhs.color != rhs.color { return lhs.color.rawValue < rhs.color.rawValue }
        return lhs.anchor < rhs.anchor
    }
}

/// 双方一致确认死棋后的终局结算。
nonisolated struct AgreedScoreOutcome: Hashable, Sendable {
    /// 面积计分明细。
    let breakdown: AreaScoreBreakdown
    /// 达成一致的审核轮次。
    let reviewID: ReviewID
    /// 双方约定的死棋块，按 ``GroupID`` 规范顺序排列。
    let agreedDeadGroups: [GroupID]
}

/// 终局结果。
nonisolated enum GameResult: Hashable, Sendable {
    /// 双方一致确认死棋后按三维面积法结算。
    case areaScore(AgreedScoreOutcome)
    /// 一方认输。
    case resignation(winner: Stone, loser: Stone)
}

/// 一方死棋提案在公共表面上的可见状态。
///
/// 第二份提交完成前，公共表面只能看到"已提交"，永远看不到集合内容。
nonisolated enum DeadGroupSubmissionStatus: Hashable, Sendable {
    /// 尚未提交。
    case notSubmitted
    /// 已提交，内容仍然隐藏。
    case submitted
    /// 双方都已提交，内容已公开。
    case revealed([GroupID])
}

/// 提供给 UI、玩家与 AR 的公共对局状态。
///
/// 它绝不包含第一方尚未公开的死棋提案内容，也不包含私有权威日志。
nonisolated struct PublicGameState: Hashable, Sendable {
    let board: Board
    let nextPlayer: Stone
    let phase: GamePhase
    let consecutivePasses: UInt8
    let capturedByBlack: UInt64
    let capturedByWhite: UInt64
    let revision: UInt64
    let reviewID: ReviewID?
    let result: GameResult?
    private let submissionStatus: [Stone: DeadGroupSubmissionStatus]

    init(
        board: Board,
        nextPlayer: Stone,
        phase: GamePhase,
        consecutivePasses: UInt8,
        capturedByBlack: UInt64,
        capturedByWhite: UInt64,
        revision: UInt64,
        reviewID: ReviewID?,
        result: GameResult?,
        submissionStatus: [Stone: DeadGroupSubmissionStatus]
    ) {
        self.board = board
        self.nextPlayer = nextPlayer
        self.phase = phase
        self.consecutivePasses = consecutivePasses
        self.capturedByBlack = capturedByBlack
        self.capturedByWhite = capturedByWhite
        self.revision = revision
        self.reviewID = reviewID
        self.result = result
        self.submissionStatus = submissionStatus
    }

    /// 指定一方死棋提案的公共可见状态。
    func deadGroupStatus(for color: Stone) -> DeadGroupSubmissionStatus {
        submissionStatus[color] ?? .notSubmitted
    }

    /// 指定一方累计提走的敌方棋子颗数。
    func capturedStones(by player: Stone) -> UInt64 {
        player == .black ? capturedByBlack : capturedByWhite
    }
}
