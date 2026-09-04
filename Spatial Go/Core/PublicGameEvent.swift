import Foundation

/// 已接受动作的脱敏摘要。
///
/// 这是公共/渲染安全边界上唯一的动作描述。它刻意不携带 ``GroupID``：
/// 完整的死棋提案载荷只存在于私有 ``GameLog`` 与 ``AuthoritativeGameState``，
/// 编译器保证任何消费公共转换的代码都拿不到第一份提案的内容。
nonisolated enum PublicActionSummary: Hashable, Sendable {
    case placed(actor: Stone, position: GridPosition)
    case passed(actor: Stone)
    case resigned(actor: Stone)
    /// 某一方已提交死棋提案；摘要不含集合内容。
    case deadGroupsSubmitted(actor: Stone)
    case resumed(actor: Stone)
}

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
