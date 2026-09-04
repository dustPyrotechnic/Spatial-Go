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

/// 快照中除棋盘以外的全部公开元数据。
///
/// 把它们收进一个值类型，是为了让"镜像必须整体跟随快照"成为一次可比较、可赋值的操作，
/// 而不是一组容易漏掉的独立字段。
nonisolated struct SnapshotMetadata: Hashable, Sendable {
    let phase: GamePhase
    let nextPlayer: Stone
    let consecutivePasses: UInt8
    let reviewID: ReviewID?
    let result: GameResult?
    /// 黑方死棋提案的公共可见状态。第二份提交前只可能是"未提交"或"已提交"。
    let blackSubmission: DeadGroupSubmissionStatus
    /// 白方死棋提案的公共可见状态。
    let whiteSubmission: DeadGroupSubmissionStatus

    init(
        phase: GamePhase,
        nextPlayer: Stone,
        consecutivePasses: UInt8,
        reviewID: ReviewID?,
        result: GameResult?,
        blackSubmission: DeadGroupSubmissionStatus,
        whiteSubmission: DeadGroupSubmissionStatus
    ) {
        self.phase = phase
        self.nextPlayer = nextPlayer
        self.consecutivePasses = consecutivePasses
        self.reviewID = reviewID
        self.result = result
        self.blackSubmission = blackSubmission
        self.whiteSubmission = whiteSubmission
    }

    /// 指定一方死棋提案的公共可见状态。
    func deadGroupStatus(for color: Stone) -> DeadGroupSubmissionStatus {
        color == .black ? blackSubmission : whiteSubmission
    }
}

/// 提供给渲染层的不可变快照。
///
/// 它只包含棋盘、公共元数据、修订号和棋盘摘要；不含权威日志，
/// 也不含第二份提交之前的死棋提案内容。
nonisolated struct GameSnapshot: Hashable, Sendable {
    let board: Board
    /// 除棋盘外的全部公开元数据。
    let metadata: SnapshotMetadata
    /// 状态修订号。只有被接受的规则动作会推进它。
    let revision: UInt64
    /// 棋盘内容的确定性摘要，不包含下一行棋方。
    let boardDigest: UInt64

    init(board: Board, metadata: SnapshotMetadata, revision: UInt64, boardDigest: UInt64) {
        self.board = board
        self.metadata = metadata
        self.revision = revision
        self.boardDigest = boardDigest
    }

    var phase: GamePhase { metadata.phase }
    var nextPlayer: Stone { metadata.nextPlayer }
    var consecutivePasses: UInt8 { metadata.consecutivePasses }
    var reviewID: ReviewID? { metadata.reviewID }
    var result: GameResult? { metadata.result }

    /// 指定一方死棋提案的公共可见状态。
    func deadGroupStatus(for color: Stone) -> DeadGroupSubmissionStatus {
        metadata.deadGroupStatus(for: color)
    }
}
