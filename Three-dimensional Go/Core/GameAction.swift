import Foundation

/// 玩家可以请求的规则动作。
///
/// 每个已接受的动作都是原子的，并以完整载荷写入权威日志。
nonisolated enum GameAction: Hashable, Codable, Sendable {
    /// 由 `actor` 在 `position` 落子。
    case place(actor: Stone, position: GridPosition)
    /// 由 `actor` 停着。
    case pass(actor: Stone)
    /// 由 `actor` 认输。
    case resign(actor: Stone)
    /// 由 `actor` 提交完整死棋块集合。
    ///
    /// 写入权威日志的载荷必须是已校验、去重并按 ``GroupID`` 规范排序后的集合，
    /// 输入顺序不得改变日志字节。
    case submitDeadGroups(actor: Stone, groups: [GroupID])
    /// 由 `actor` 请求恢复对局。
    case resume(actor: Stone)

    /// 请求该动作的一方。
    var actor: Stone {
        switch self {
        case let .place(actor, _): actor
        case let .pass(actor): actor
        case let .resign(actor): actor
        case let .submitDeadGroups(actor, _): actor
        case let .resume(actor): actor
        }
    }
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
    /// 本次转换对外发布的公共事件，按发生顺序排列。
    let events: [PublicGameEvent]
}
