import Foundation

/// 创建对局时可能出现的稳定错误类型。
nonisolated enum GameConfigurationError: Error, Equatable, Sendable {
    /// 某个维度不在 `1...19` 范围内。
    case dimensionOutOfRange(axis: BoardAxis, value: Int)
    /// 初始布子坐标落在棋盘外。
    case initialStoneOutOfBounds(GridPosition)
    /// 同一坐标被重复布子。
    case duplicateInitialStone(GridPosition)
    /// 初始布子完成后存在没有气的棋块，`anchor` 为该棋块字典序最小坐标。
    case initialGroupWithoutLiberty(anchor: GridPosition)
}

/// 一局三维围棋的创建参数。
///
/// 校验通过后 ``initialStones`` 已按锚点顺序规范排序，``board`` 是应用初始布子后的棋盘。
nonisolated struct GameConfiguration: Hashable, Sendable {
    /// 白方默认贴目，以半目为单位，13 即 6.5 目。
    static let defaultKomiHalfPoints: UInt16 = 13

    let width: Int
    let height: Int
    let depth: Int
    let komiHalfPoints: UInt16
    let nextPlayer: Stone
    let initialStones: [PlacedStone]
    let board: Board

    /// 创建并校验对局配置。
    ///
    /// - Parameters:
    ///   - width: x 方向交叉点数，取值 `1...19`。
    ///   - height: y 方向交叉点数，取值 `1...19`。
    ///   - depth: z 方向层数，取值 `1...19`。
    ///   - komiHalfPoints: 白方贴目半目数，缺省 13。
    ///   - nextPlayer: 下一行棋方，缺省黑。
    ///   - initialStones: 教学初始布子，要求坐标唯一、在盘内，且布置完成后每个棋块至少有一气。
    /// - Throws: 校验失败时抛出 ``GameConfigurationError``。
    init(
        width: Int,
        height: Int,
        depth: Int,
        komiHalfPoints: UInt16 = GameConfiguration.defaultKomiHalfPoints,
        nextPlayer: Stone = .black,
        initialStones: [PlacedStone] = []
    ) throws {
        var board = try Board(width: width, height: height, depth: depth)
        var seen = Set<GridPosition>()
        for stone in initialStones {
            guard board.contains(stone.position) else {
                throw GameConfigurationError.initialStoneOutOfBounds(stone.position)
            }
            guard seen.insert(stone.position).inserted else {
                throw GameConfigurationError.duplicateInitialStone(stone.position)
            }
            board[stone.position] = stone.stone
        }

        var checked = Set<GridPosition>()
        for stone in initialStones where !checked.contains(stone.position) {
            guard let group = board.groupAndLiberties(at: stone.position) else { continue }
            checked.formUnion(group.stones)
            guard !group.liberties.isEmpty else {
                throw GameConfigurationError.initialGroupWithoutLiberty(
                    anchor: group.stones.min() ?? stone.position
                )
            }
        }

        self.width = width
        self.height = height
        self.depth = depth
        self.komiHalfPoints = komiHalfPoints
        self.nextPlayer = nextPlayer
        self.initialStones = initialStones.sorted { $0.position < $1.position }
        self.board = board
    }
}
