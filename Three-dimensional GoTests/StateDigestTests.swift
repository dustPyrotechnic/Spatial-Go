import Testing

@testable import Three_dimensional_Go

/// `StateKey` 规范序列化、`StateKeyDigestV1` 金标向量，以及情境超级劫行为测试。
struct StateDigestTests {

    /// 恒定摘要实现：用于证明摘要碰撞本身永远不能拒绝一个不相等的状态。
    private struct ConstantDigester: StateKeyDigesting {
        func digest(_ key: StateKey) -> UInt64 { 0 }
    }

    // MARK: - 规范序列化

    @Test func stateKeyBoardBytesFollowCanonicalZThenYThenXOrder() throws {
        var board = try Board(width: 2, height: 1, depth: 2)
        board[GridPosition(x: 0, y: 0, z: 0)] = .black
        board[GridPosition(x: 0, y: 0, z: 1)] = .white
        board[GridPosition(x: 1, y: 0, z: 1)] = .black
        let key = StateKey(board: board, nextPlayer: .black)
        #expect(key.boardBytes == [1, 0, 2, 1])
        #expect(key.canonicalBytes == [2, 1, 2, 1, 0, 2, 1, 1])
        #expect(StateKey(board: board, nextPlayer: .white).canonicalBytes.last == 2)
    }

    @Test func stateKeyDistinguishesNextPlayerOnIdenticalBoards() throws {
        let board = try Board(width: 3, height: 3, depth: 1)
        #expect(StateKey(board: board, nextPlayer: .black) != StateKey(board: board, nextPlayer: .white))
    }

    // MARK: - 金标摘要向量

    @Test func goldenDigestForEmptySinglePointBoard() throws {
        let board = try Board(width: 1, height: 1, depth: 1)
        let digester = StateKeyDigestV1()
        #expect(digester.digest(StateKey(board: board, nextPlayer: .black)) == 0x3869_cb0b_3026_d098)
        #expect(digester.digest(StateKey(board: board, nextPlayer: .white)) == 0x3869_ce0b_3026_d5b1)
    }

    @Test func goldenDigestForAsymmetricTwoByOneByTwoBoard() throws {
        var board = try Board(width: 2, height: 1, depth: 2)
        board[GridPosition(x: 0, y: 0, z: 0)] = .black
        board[GridPosition(x: 0, y: 0, z: 1)] = .white
        board[GridPosition(x: 1, y: 0, z: 1)] = .black
        let digester = StateKeyDigestV1()
        #expect(digester.digest(StateKey(board: board, nextPlayer: .black)) == 0x3e77_7dc6_ce29_d07e)
        #expect(digester.digest(StateKey(board: board, nextPlayer: .white)) == 0x3e77_7cc6_ce29_cecb)
    }

    // MARK: - 创建即入历史

    @Test func initialStateKeyIsRecordedAtCreation() throws {
        let configuration = try GameConfiguration(width: 3, height: 3, depth: 1)
        let engine = RuleEngine(configuration: configuration)
        let digester = StateKeyDigestV1()
        let key = StateKey(board: configuration.board, nextPlayer: .black)
        #expect(engine.state.superkoSeen.contains(key, digest: digester.digest(key)))
        #expect(engine.state.superkoSeen.count == 1)
    }

    // MARK: - 劫与超级劫

    /// 单劫棋形：黑提一子后，白立即回提会重建创建时即写入历史的初始局面。
    @Test func rejectsRecaptureThatRecreatesTheInitialState() throws {
        var engine = RuleEngine(configuration: try StateDigestTests.singleKoConfiguration())
        let transition = try engine.apply(
            .place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        #expect(transition.capturedPositions == [GridPosition(x: 2, y: 1, z: 0)])
        expectAtomicRejection(
            &engine, .place(actor: .white, position: GridPosition(x: 2, y: 1, z: 0)), .superko)
    }

    /// 三劫棋盘上，白提二号劫后黑立即回提，会重建由已接受动作产生的中间局面。
    @Test func rejectsImmediateRecaptureOfMidGameState() throws {
        var engine = RuleEngine(configuration: try StateDigestTests.tripleKoConfiguration())
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        _ = try engine.apply(.place(actor: .white, position: GridPosition(x: 6, y: 1, z: 0)))
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 7, y: 1, z: 0)), .superko)
    }

    /// 三劫循环：六手之后棋盘和行棋方同时回到初始局面，必须由情境超级劫拒绝。
    @Test func rejectsLongerRepeatedStateAfterSixPlies() throws {
        var engine = RuleEngine(configuration: try StateDigestTests.tripleKoConfiguration())
        let opening: [(Stone, GridPosition)] = [
            (.black, GridPosition(x: 1, y: 1, z: 0)),
            (.white, GridPosition(x: 6, y: 1, z: 0)),
            (.black, GridPosition(x: 11, y: 1, z: 0)),
            (.white, GridPosition(x: 2, y: 1, z: 0)),
            (.black, GridPosition(x: 7, y: 1, z: 0)),
        ]
        for (actor, position) in opening {
            _ = try engine.apply(.place(actor: actor, position: position))
        }
        #expect(engine.state.revision == 5)
        expectAtomicRejection(
            &engine, .place(actor: .white, position: GridPosition(x: 12, y: 1, z: 0)), .superko)
        #expect(engine.state.superkoSeen.count == 6)
    }

    // MARK: - 摘要碰撞

    /// 恒定摘要下所有状态都命中同一个桶；只有完整 `StateKey` 相等才允许拒绝。
    @Test func digestCollisionAloneNeverRejectsUnequalStates() throws {
        let configuration = try GameConfiguration(width: 3, height: 3, depth: 1)
        var engine = RuleEngine(configuration: configuration, digester: ConstantDigester())
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0)))
        _ = try engine.apply(.place(actor: .white, position: GridPosition(x: 2, y: 2, z: 0)))
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        #expect(engine.state.revision == 3)
        #expect(engine.state.superkoSeen.count == 4)
    }

    @Test func realRepetitionIsStillRejectedUnderCollidingDigests() throws {
        var engine = RuleEngine(
            configuration: try StateDigestTests.singleKoConfiguration(),
            digester: ConstantDigester()
        )
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        expectAtomicRejection(
            &engine, .place(actor: .white, position: GridPosition(x: 2, y: 1, z: 0)), .superko)
    }

    // MARK: - 棋形夹具

    /// 4×3×1 单劫棋形，黑先。黑在 `(1,1,0)` 提掉白 `(2,1,0)`，白回提即重复初始局面。
    static func singleKoConfiguration() throws -> GameConfiguration {
        try GameConfiguration(
            width: 4, height: 3, depth: 1,
            initialStones: koShape(offsetX: 0, capturable: .white)
        )
    }

    /// 14×3×1 三劫棋盘，三个互不相邻的劫分别可由黑、白、黑先提。
    static func tripleKoConfiguration() throws -> GameConfiguration {
        try GameConfiguration(
            width: 14, height: 3, depth: 1,
            initialStones: koShape(offsetX: 0, capturable: .white)
                + koShape(offsetX: 5, capturable: .black)
                + koShape(offsetX: 10, capturable: .white)
        )
    }

    /// 生成一个单层劫棋形。
    ///
    /// - Parameters:
    ///   - offsetX: 棋形最左列的 x 偏移。
    ///   - capturable: 处于被提状态的一方；其对手可以在 `(offsetX + 1, 1)` 提子。
    /// - Returns: 该棋形的全部初始布子。
    static func koShape(offsetX: Int, capturable: Stone) -> [PlacedStone] {
        let taker = capturable.opponent
        func position(_ x: Int, _ y: Int) -> GridPosition {
            GridPosition(x: offsetX + x, y: y, z: 0)
        }
        return [
            PlacedStone(position: position(2, 1), stone: capturable),
            PlacedStone(position: position(3, 1), stone: taker),
            PlacedStone(position: position(2, 0), stone: taker),
            PlacedStone(position: position(2, 2), stone: taker),
            PlacedStone(position: position(0, 1), stone: capturable),
            PlacedStone(position: position(1, 0), stone: capturable),
            PlacedStone(position: position(1, 2), stone: capturable),
        ]
    }
}
