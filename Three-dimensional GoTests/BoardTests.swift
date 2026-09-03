import Testing

@testable import Three_dimensional_Go

/// Board 与对局配置的基础值类型测试，覆盖维度边界、零基坐标、线性索引往返、
/// 规范 z/y/x 遍历顺序，以及 `3d-go/1` 的教学初始布子校验。
struct BoardTests {

    // MARK: - 维度边界

    @Test func rejectsDimensionsBelowMinimum() {
        #expect(throws: GameConfigurationError.dimensionOutOfRange(axis: .x, value: 0)) {
            _ = try Board(width: 0, height: 1, depth: 1)
        }
        #expect(throws: GameConfigurationError.dimensionOutOfRange(axis: .y, value: -1)) {
            _ = try Board(width: 1, height: -1, depth: 1)
        }
        #expect(throws: GameConfigurationError.dimensionOutOfRange(axis: .z, value: 0)) {
            _ = try Board(width: 1, height: 1, depth: 0)
        }
    }

    @Test func rejectsDimensionsAboveMaximum() {
        #expect(throws: GameConfigurationError.dimensionOutOfRange(axis: .x, value: 20)) {
            _ = try Board(width: 20, height: 19, depth: 19)
        }
        #expect(throws: GameConfigurationError.dimensionOutOfRange(axis: .y, value: 20)) {
            _ = try Board(width: 19, height: 20, depth: 19)
        }
        #expect(throws: GameConfigurationError.dimensionOutOfRange(axis: .z, value: 20)) {
            _ = try Board(width: 19, height: 19, depth: 20)
        }
    }

    @Test func acceptsFullNineteenCubedBoard() throws {
        let board = try Board(width: 19, height: 19, depth: 19)
        #expect(board.pointCount == 6859)
        #expect(board.canonicalPositions.count == 6859)
        #expect(board[GridPosition(x: 18, y: 18, z: 18)] == nil)
    }

    // MARK: - 1×1×1 边界

    @Test func singlePointBoardHasExactlyOnePoint() throws {
        let board = try Board(width: 1, height: 1, depth: 1)
        #expect(board.pointCount == 1)
        #expect(board.canonicalPositions == [GridPosition(x: 0, y: 0, z: 0)])
        #expect(board.contains(GridPosition(x: 0, y: 0, z: 0)))
        #expect(!board.contains(GridPosition(x: 1, y: 0, z: 0)))
    }

    @Test func singlePointBoardCannotHoldAnInitialStone() {
        let stone = PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black)
        #expect(
            throws: GameConfigurationError.initialGroupWithoutLiberty(
                anchor: GridPosition(x: 0, y: 0, z: 0)
            )
        ) {
            _ = try GameConfiguration(width: 1, height: 1, depth: 1, initialStones: [stone])
        }
    }

    // MARK: - 零基坐标

    @Test func coordinatesAreZeroBased() throws {
        let board = try Board(width: 2, height: 3, depth: 4)
        #expect(board.contains(GridPosition(x: 0, y: 0, z: 0)))
        #expect(board.contains(GridPosition(x: 1, y: 2, z: 3)))
        #expect(!board.contains(GridPosition(x: -1, y: 0, z: 0)))
        #expect(!board.contains(GridPosition(x: 0, y: -1, z: 0)))
        #expect(!board.contains(GridPosition(x: 0, y: 0, z: -1)))
        #expect(!board.contains(GridPosition(x: 2, y: 2, z: 3)))
        #expect(!board.contains(GridPosition(x: 1, y: 3, z: 3)))
        #expect(!board.contains(GridPosition(x: 1, y: 2, z: 4)))
    }

    // MARK: - 线性索引往返

    @Test func linearIndexUsesXPlusWidthTimesYPlusHeightTimesZ() throws {
        let board = try Board(width: 3, height: 4, depth: 5)
        #expect(board.linearIndex(of: GridPosition(x: 0, y: 0, z: 0)) == 0)
        #expect(board.linearIndex(of: GridPosition(x: 2, y: 0, z: 0)) == 2)
        #expect(board.linearIndex(of: GridPosition(x: 0, y: 1, z: 0)) == 3)
        #expect(board.linearIndex(of: GridPosition(x: 0, y: 0, z: 1)) == 12)
        #expect(board.linearIndex(of: GridPosition(x: 2, y: 3, z: 4)) == 59)
    }

    @Test func linearIndexRoundTripsForEveryPoint() throws {
        let board = try Board(width: 3, height: 4, depth: 5)
        for index in 0..<board.pointCount {
            let position = board.position(atLinearIndex: index)
            #expect(board.contains(position))
            #expect(board.linearIndex(of: position) == index)
        }
    }

    // MARK: - 规范 z/y/x 遍历

    @Test func canonicalTraversalAdvancesXFirstThenYThenZ() throws {
        let board = try Board(width: 2, height: 2, depth: 2)
        #expect(
            board.canonicalPositions == [
                GridPosition(x: 0, y: 0, z: 0),
                GridPosition(x: 1, y: 0, z: 0),
                GridPosition(x: 0, y: 1, z: 0),
                GridPosition(x: 1, y: 1, z: 0),
                GridPosition(x: 0, y: 0, z: 1),
                GridPosition(x: 1, y: 0, z: 1),
                GridPosition(x: 0, y: 1, z: 1),
                GridPosition(x: 1, y: 1, z: 1),
            ]
        )
    }

    /// 锚点顺序（x → y → z 字典序）与棋盘序列化顺序（z → y → x）是两套独立顺序。
    @Test func anchorOrderingIsLexicographicByXThenYThenZ() {
        let positions = [
            GridPosition(x: 1, y: 0, z: 0),
            GridPosition(x: 0, y: 1, z: 1),
            GridPosition(x: 0, y: 0, z: 2),
            GridPosition(x: 0, y: 1, z: 0),
        ]
        #expect(positions.min() == GridPosition(x: 0, y: 0, z: 2))
        #expect(
            positions.sorted() == [
                GridPosition(x: 0, y: 0, z: 2),
                GridPosition(x: 0, y: 1, z: 0),
                GridPosition(x: 0, y: 1, z: 1),
                GridPosition(x: 1, y: 0, z: 0),
            ]
        )
    }

    // MARK: - 配置缺省值

    @Test func configurationDefaultsToBlackNextAndSixAndAHalfKomi() throws {
        let configuration = try GameConfiguration(width: 9, height: 9, depth: 1)
        #expect(configuration.nextPlayer == .black)
        #expect(configuration.komiHalfPoints == 13)
        #expect(configuration.initialStones.isEmpty)
        #expect(configuration.board.pointCount == 81)
    }

    @Test func configurationPropagatesDimensionErrors() {
        #expect(throws: GameConfigurationError.dimensionOutOfRange(axis: .z, value: 20)) {
            _ = try GameConfiguration(width: 19, height: 19, depth: 20)
        }
    }

    // MARK: - 初始布子校验

    @Test func rejectsInitialStoneOutOfBounds() {
        let stone = PlacedStone(position: GridPosition(x: 3, y: 0, z: 0), stone: .black)
        #expect(
            throws: GameConfigurationError.initialStoneOutOfBounds(GridPosition(x: 3, y: 0, z: 0))
        ) {
            _ = try GameConfiguration(width: 3, height: 3, depth: 1, initialStones: [stone])
        }
    }

    @Test func rejectsDuplicateInitialStone() {
        let position = GridPosition(x: 1, y: 1, z: 0)
        let stones = [
            PlacedStone(position: position, stone: .black),
            PlacedStone(position: position, stone: .white),
        ]
        #expect(throws: GameConfigurationError.duplicateInitialStone(position)) {
            _ = try GameConfiguration(width: 3, height: 3, depth: 1, initialStones: stones)
        }
    }

    /// 3×3×1 上被白棋完全包围的两子黑块没有气，必须以字典序最小坐标为锚点拒绝。
    @Test func rejectsInitialGroupWithoutLiberty() {
        let stones = [
            PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
            PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .black),
            PlacedStone(position: GridPosition(x: 2, y: 0, z: 0), stone: .white),
            PlacedStone(position: GridPosition(x: 0, y: 1, z: 0), stone: .white),
            PlacedStone(position: GridPosition(x: 1, y: 1, z: 0), stone: .white),
        ]
        #expect(
            throws: GameConfigurationError.initialGroupWithoutLiberty(
                anchor: GridPosition(x: 0, y: 0, z: 0)
            )
        ) {
            _ = try GameConfiguration(width: 3, height: 3, depth: 1, initialStones: stones)
        }
    }

    /// 同一形状在 depth = 2 时，黑块获得向上的一口气，因而必须被接受。
    @Test func acceptsInitialGroupWithVerticalLibertyOnly() throws {
        let stones = [
            PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
            PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .black),
            PlacedStone(position: GridPosition(x: 2, y: 0, z: 0), stone: .white),
            PlacedStone(position: GridPosition(x: 0, y: 1, z: 0), stone: .white),
            PlacedStone(position: GridPosition(x: 1, y: 1, z: 0), stone: .white),
        ]
        let configuration = try GameConfiguration(
            width: 3,
            height: 3,
            depth: 2,
            initialStones: stones
        )
        #expect(configuration.board[GridPosition(x: 0, y: 0, z: 0)] == .black)
        #expect(configuration.board[GridPosition(x: 2, y: 0, z: 0)] == .white)
        #expect(configuration.board[GridPosition(x: 0, y: 0, z: 1)] == nil)
    }

    @Test func acceptedInitialStonesAreStoredInAnchorOrder() throws {
        let stones = [
            PlacedStone(position: GridPosition(x: 1, y: 1, z: 0), stone: .white),
            PlacedStone(position: GridPosition(x: 0, y: 2, z: 0), stone: .black),
            PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
        ]
        let configuration = try GameConfiguration(
            width: 3,
            height: 3,
            depth: 1,
            komiHalfPoints: 0,
            nextPlayer: .white,
            initialStones: stones
        )
        #expect(
            configuration.initialStones.map(\.position) == [
                GridPosition(x: 0, y: 0, z: 0),
                GridPosition(x: 0, y: 2, z: 0),
                GridPosition(x: 1, y: 1, z: 0),
            ]
        )
        #expect(configuration.nextPlayer == .white)
        #expect(configuration.komiHalfPoints == 0)
    }

    @Test func stoneOpponentIsSymmetric() {
        #expect(Stone.black.opponent == .white)
        #expect(Stone.white.opponent == .black)
        #expect(Stone.black.rawValue == 1)
        #expect(Stone.white.rawValue == 2)
    }
}
