import Foundation

/// 棋盘上的一颗棋子颜色。
nonisolated enum Stone: UInt8, Codable, Sendable, CaseIterable {
    case black = 1
    case white = 2

    /// 对方颜色。
    var opponent: Stone { self == .black ? .white : .black }
}

/// 棋盘的一个维度轴，用于报告稳定的维度错误。
nonisolated enum BoardAxis: String, Codable, Sendable, CaseIterable {
    case x
    case y
    case z
}

/// 一颗放置在具体坐标上的棋子。
nonisolated struct PlacedStone: Hashable, Codable, Sendable {
    let position: GridPosition
    let stone: Stone

    init(position: GridPosition, stone: Stone) {
        self.position = position
        self.stone = stone
    }
}

/// 有限 `width × height × depth` 的三维棋盘。
///
/// 内部使用连续一维数组存储，索引为 `x + width × (y + height × z)`；
/// 邻接关系只有六个正交方向，棋盘外部不是节点。
nonisolated struct Board: Hashable, Sendable {
    /// 每个维度允许的最小值。
    static let minimumDimension = 1
    /// 每个维度允许的最大值。
    static let maximumDimension = 19

    let width: Int
    let height: Int
    let depth: Int

    /// 按规范 z/y/x 顺序展开的连续棋盘存储。
    private(set) var cells: [Stone?]

    /// 创建空棋盘。
    ///
    /// - Parameters:
    ///   - width: x 方向交叉点数，取值 `1...19`。
    ///   - height: y 方向交叉点数，取值 `1...19`。
    ///   - depth: z 方向层数，取值 `1...19`。
    /// - Throws: 任一维度越界时抛出 ``GameConfigurationError/dimensionOutOfRange(axis:value:)``。
    init(width: Int, height: Int, depth: Int) throws {
        try Board.validate(dimension: width, axis: .x)
        try Board.validate(dimension: height, axis: .y)
        try Board.validate(dimension: depth, axis: .z)
        self.width = width
        self.height = height
        self.depth = depth
        self.cells = [Stone?](repeating: nil, count: width * height * depth)
    }

    private static func validate(dimension: Int, axis: BoardAxis) throws {
        guard (minimumDimension...maximumDimension).contains(dimension) else {
            throw GameConfigurationError.dimensionOutOfRange(axis: axis, value: dimension)
        }
    }

    /// 棋盘交叉点总数。
    var pointCount: Int { cells.count }

    /// 判断坐标是否落在棋盘内。
    func contains(_ position: GridPosition) -> Bool {
        (0..<width).contains(position.x)
            && (0..<height).contains(position.y)
            && (0..<depth).contains(position.z)
    }

    /// 计算坐标对应的连续存储索引。调用方必须先确认坐标在棋盘内。
    func linearIndex(of position: GridPosition) -> Int {
        position.x + width * (position.y + height * position.z)
    }

    /// 由连续存储索引还原坐标。
    func position(atLinearIndex index: Int) -> GridPosition {
        let x = index % width
        let rest = index / width
        return GridPosition(x: x, y: rest % height, z: rest / height)
    }

    /// 按规范 z、再 y、再 x 顺序展开的全部坐标。
    var canonicalPositions: [GridPosition] {
        (0..<pointCount).map(position(atLinearIndex:))
    }

    subscript(position: GridPosition) -> Stone? {
        get { cells[linearIndex(of: position)] }
        set { cells[linearIndex(of: position)] = newValue }
    }

    /// 与给定坐标六向正交相邻且仍在棋盘内的坐标。
    func neighbors(of position: GridPosition) -> [GridPosition] {
        var result = [GridPosition]()
        result.reserveCapacity(6)
        let candidates = [
            GridPosition(x: position.x - 1, y: position.y, z: position.z),
            GridPosition(x: position.x + 1, y: position.y, z: position.z),
            GridPosition(x: position.x, y: position.y - 1, z: position.z),
            GridPosition(x: position.x, y: position.y + 1, z: position.z),
            GridPosition(x: position.x, y: position.y, z: position.z - 1),
            GridPosition(x: position.x, y: position.y, z: position.z + 1),
        ]
        for candidate in candidates where contains(candidate) {
            result.append(candidate)
        }
        return result
    }

    /// 同色六向连通棋块及其气。
    ///
    /// - Parameter position: 棋块内任意一个已有棋子的坐标。
    /// - Returns: 棋块全部坐标与不同气点集合；坐标为空点时返回 `nil`。
    ///   `stones` 的顺序由遍历过程决定，未作规定，调用方不得依赖它。
    func groupAndLiberties(at position: GridPosition) -> (stones: [GridPosition], liberties: Set<GridPosition>)? {
        guard contains(position), let color = self[position] else { return nil }
        var visited: Set<GridPosition> = [position]
        var pending = [position]
        var stones = [GridPosition]()
        var liberties = Set<GridPosition>()
        while let current = pending.popLast() {
            stones.append(current)
            for neighbor in neighbors(of: current) {
                switch self[neighbor] {
                case .none:
                    liberties.insert(neighbor)
                case .some(let neighborColor) where neighborColor == color:
                    if visited.insert(neighbor).inserted {
                        pending.append(neighbor)
                    }
                case .some:
                    continue
                }
            }
        }
        return (stones, liberties)
    }
}
