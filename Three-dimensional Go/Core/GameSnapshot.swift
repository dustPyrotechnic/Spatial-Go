import Foundation

/// 棋盘上单个交叉点的变化量。
///
/// `stone` 为 `nil` 表示该点变为空点。展示层只消费已经算好的增量，从不反写规则状态。
nonisolated struct BoardDelta: Hashable, Sendable {
    let position: GridPosition
    let stone: Stone?

    init(position: GridPosition, stone: Stone?) {
        self.position = position
        self.stone = stone
    }
}

/// 提供给渲染层的不可变快照。
///
/// 它只包含棋盘、公共阶段与状态、修订号和棋盘摘要；不含权威日志，
/// 也不含第二份提交之前的死棋提案内容。
nonisolated struct GameSnapshot: Hashable, Sendable {
    let board: Board
    let phase: GamePhase
    let nextPlayer: Stone
    let consecutivePasses: UInt8
    let reviewID: ReviewID?
    let result: GameResult?
    /// 状态修订号。只有被接受的规则动作会推进它。
    let revision: UInt64
    /// 棋盘内容的确定性摘要，不包含下一行棋方。
    let boardDigest: UInt64
    private let submissionStatus: [Stone: DeadGroupSubmissionStatus]

    init(
        board: Board,
        phase: GamePhase,
        nextPlayer: Stone,
        consecutivePasses: UInt8,
        reviewID: ReviewID?,
        result: GameResult?,
        revision: UInt64,
        boardDigest: UInt64,
        submissionStatus: [Stone: DeadGroupSubmissionStatus]
    ) {
        self.board = board
        self.phase = phase
        self.nextPlayer = nextPlayer
        self.consecutivePasses = consecutivePasses
        self.reviewID = reviewID
        self.result = result
        self.revision = revision
        self.boardDigest = boardDigest
        self.submissionStatus = submissionStatus
    }

    /// 指定一方死棋提案的公共可见状态。
    func deadGroupStatus(for color: Stone) -> DeadGroupSubmissionStatus {
        submissionStatus[color] ?? .notSubmitted
    }
}
