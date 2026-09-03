import Foundation

/// 玩家可以请求的规则动作。
///
/// 每个已接受的动作都是原子的，并以完整载荷写入权威日志。
nonisolated enum GameAction: Hashable, Codable, Sendable {
    /// 由 `actor` 在 `position` 落子。
    case place(actor: Stone, position: GridPosition)
}

/// 一次已接受动作产生的状态变化量。
///
/// 展示层只消费这里的增量，不反写规则状态。
nonisolated struct GameTransition: Hashable, Sendable {
    /// 被接受的动作。
    let action: GameAction
    /// 接受该动作后的状态修订号。
    let revision: UInt64
    /// 本次新增的棋子，停着一类动作为 `nil`。
    let placedStone: PlacedStone?
    /// 本次被提走的棋子坐标，按棋盘规范 z/y/x 顺序排列。
    let capturedPositions: [GridPosition]
    /// 接受该动作后的下一行棋方。
    let nextPlayer: Stone
}
