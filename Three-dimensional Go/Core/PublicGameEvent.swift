import Foundation

/// 已接受动作产生的公共事件。
///
/// 与 ``PublicGameState`` 一样，它在双方都提交之前绝不携带死棋提案内容。
nonisolated enum PublicGameEvent: Hashable, Sendable {
    /// 落子被接受，并同时移除了 `captured` 中的敌方棋子。
    case placed(actor: Stone, position: GridPosition, captured: [GridPosition], revision: UInt64)
    /// 停着被接受。
    case passed(actor: Stone, consecutivePasses: UInt8, revision: UInt64)
    /// 连续两次停着后进入计分审核。
    case enteredScoringReview(reviewID: ReviewID, revision: UInt64)
    /// 一方已提交死棋提案；本事件不携带集合内容。
    case deadGroupsSubmitted(actor: Stone, revision: UInt64)
    /// 双方都已提交，公开两份集合以及是否一致。
    case deadGroupsRevealed(black: [GroupID], white: [GroupID], agreed: Bool, revision: UInt64)
    /// 恢复对局。
    case resumed(actor: Stone, nextPlayer: Stone, revision: UInt64)
    /// 一方认输。
    case resigned(actor: Stone, revision: UInt64)
    /// 棋局结束。
    case finished(result: GameResult, revision: UInt64)
}
