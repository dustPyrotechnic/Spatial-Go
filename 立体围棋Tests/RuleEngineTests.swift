import Testing

@testable import 立体围棋

/// `3d-go/1` 落子事务测试：六向邻接、棋块与气、提子、自杀禁止，
/// 以及每一个被拒绝动作的完整状态原子性。
struct RuleEngineTests {

    private func engine(
        width: Int,
        height: Int,
        depth: Int,
        nextPlayer: Stone = .black,
        initialStones: [PlacedStone] = []
    ) throws -> RuleEngine {
        let configuration = try GameConfiguration(
            width: width,
            height: height,
            depth: depth,
            nextPlayer: nextPlayer,
            initialStones: initialStones
        )
        return RuleEngine(configuration: configuration)
    }

    // MARK: - 六向邻接

    @Test func neighborCountsByBoardRegion() throws {
        let board = try Board(width: 3, height: 3, depth: 3)
        #expect(board.neighbors(of: GridPosition(x: 1, y: 1, z: 1)).count == 6)
        #expect(board.neighbors(of: GridPosition(x: 1, y: 1, z: 0)).count == 5)
        #expect(board.neighbors(of: GridPosition(x: 1, y: 0, z: 0)).count == 4)
        #expect(board.neighbors(of: GridPosition(x: 0, y: 0, z: 0)).count == 3)
        #expect(
            Set(board.neighbors(of: GridPosition(x: 0, y: 0, z: 0))) == [
                GridPosition(x: 1, y: 0, z: 0),
                GridPosition(x: 0, y: 1, z: 0),
                GridPosition(x: 0, y: 0, z: 1),
            ]
        )
    }

    @Test func singleLayerBoardHasNoVerticalNeighbors() throws {
        let board = try Board(width: 3, height: 3, depth: 1)
        #expect(board.neighbors(of: GridPosition(x: 1, y: 1, z: 0)).count == 4)
    }

    // MARK: - 棋块与气

    @Test func connectedGroupCountsDistinctLibertiesOnce() throws {
        let stones = [
            PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
            PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .black),
        ]
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1, initialStones: stones)
        let group = try #require(
            configuration.board.groupAndLiberties(at: GridPosition(x: 0, y: 0, z: 0)))
        #expect(Set(group.stones) == Set(stones.map(\.position)))
        #expect(
            group.liberties == [
                GridPosition(x: 2, y: 0, z: 0),
                GridPosition(x: 0, y: 1, z: 0),
                GridPosition(x: 1, y: 1, z: 0),
            ]
        )
    }

    @Test func groupsConnectVerticallyAcrossLayers() throws {
        let stones = [
            PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
            PlacedStone(position: GridPosition(x: 0, y: 0, z: 1), stone: .black),
        ]
        let configuration = try GameConfiguration(
            width: 2, height: 2, depth: 2, initialStones: stones)
        let group = try #require(
            configuration.board.groupAndLiberties(at: GridPosition(x: 0, y: 0, z: 1)))
        #expect(group.stones.count == 2)
        #expect(
            group.liberties == [
                GridPosition(x: 1, y: 0, z: 0),
                GridPosition(x: 0, y: 1, z: 0),
                GridPosition(x: 1, y: 0, z: 1),
                GridPosition(x: 0, y: 1, z: 1),
            ]
        )
    }

    @Test func sameColorStonesTouchingOnlyDiagonallyAreSeparateGroups() throws {
        let stones = [
            PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
            PlacedStone(position: GridPosition(x: 1, y: 1, z: 0), stone: .black),
        ]
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1, initialStones: stones)
        let group = try #require(
            configuration.board.groupAndLiberties(at: GridPosition(x: 0, y: 0, z: 0)))
        #expect(group.stones == [GridPosition(x: 0, y: 0, z: 0)])
    }

    // MARK: - 提子

    @Test func capturesSingleEnemyStone() throws {
        var engine = try engine(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .black),
            ]
        )
        let transition = try engine.apply(
            .place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)))
        #expect(transition.capturedPositions == [GridPosition(x: 0, y: 0, z: 0)])
        #expect(engine.state.board[GridPosition(x: 0, y: 0, z: 0)] == nil)
        #expect(engine.state.board[GridPosition(x: 0, y: 1, z: 0)] == .black)
        #expect(engine.state.capturedStones(by: .black) == 1)
        #expect(engine.state.capturedStones(by: .white) == 0)
        #expect(engine.state.nextPlayer == .white)
        #expect(engine.state.revision == 1)
        #expect(transition.revision == 1)
    }

    @Test func capturesTwoEnemyGroupsSimultaneously() throws {
        var engine = try engine(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 2, y: 0, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 0, y: 2, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 2, y: 2, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 1, y: 2, z: 0), stone: .white),
            ]
        )
        let transition = try engine.apply(
            .place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        #expect(
            transition.capturedPositions == [
                GridPosition(x: 1, y: 0, z: 0),
                GridPosition(x: 1, y: 2, z: 0),
            ]
        )
        #expect(engine.state.capturedStones(by: .black) == 2)
        #expect(engine.state.board[GridPosition(x: 1, y: 0, z: 0)] == nil)
        #expect(engine.state.board[GridPosition(x: 1, y: 2, z: 0)] == nil)
    }

    @Test func captureCountsStonesNotGroups() throws {
        var engine = try engine(
            width: 2, height: 2, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 0, y: 1, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 1, y: 1, z: 0), stone: .white),
            ]
        )
        let transition = try engine.apply(
            .place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0)))
        #expect(transition.capturedPositions.count == 3)
        #expect(engine.state.capturedStones(by: .black) == 3)
    }

    /// 己方棋在提子前没有气，提子后获得气，因此不是自杀。
    @Test func placementIsLegalWhenCaptureCreatesLiberty() throws {
        var engine = try engine(
            width: 2, height: 2, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 0, y: 1, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 1, y: 1, z: 0), stone: .white),
            ]
        )
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0)))
        let group = try #require(
            engine.state.board.groupAndLiberties(at: GridPosition(x: 0, y: 0, z: 0)))
        #expect(group.liberties.count == 2)
    }

    // MARK: - 自杀禁止与非法落子原子性

    @Test func rejectsSuicideAtomically() throws {
        var engine = try engine(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 0, y: 1, z: 0), stone: .white),
            ]
        )
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0)), .suicide)
    }

    @Test func rejectsMultiStoneSuicideAtomically() throws {
        var engine = try engine(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 0, y: 2, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 1, y: 1, z: 0), stone: .white),
            ]
        )
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)), .suicide)
    }

    @Test func rejectsOccupiedPointAtomically() throws {
        var engine = try engine(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 1, y: 1, z: 0), stone: .white)
            ]
        )
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)), .occupied)
    }

    @Test func rejectsOutOfBoundsPointAtomically() throws {
        var engine = try engine(width: 3, height: 3, depth: 1)
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 3, y: 0, z: 0)), .outOfBounds)
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 0, y: -1, z: 0)), .outOfBounds)
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 0, y: 0, z: 1)), .outOfBounds)
    }

    @Test func rejectsWrongPlayerAtomically() throws {
        var engine = try engine(width: 3, height: 3, depth: 1)
        expectAtomicRejection(
            &engine, .place(actor: .white, position: GridPosition(x: 0, y: 0, z: 0)), .wrongPlayer)
    }

    @Test func rejectsPlacementOutsidePlayingPhaseAtomically() throws {
        let configuration = try GameConfiguration(width: 3, height: 3, depth: 1)
        let state = GameState(
            configuration: configuration,
            board: configuration.board,
            nextPlayer: .black,
            phase: .finished,
            capturedByBlack: 0,
            capturedByWhite: 0,
            revision: 4
        )
        var engine = RuleEngine(state: state)
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0)), .wrongPhase)
    }

    // MARK: - 轮次推进

    @Test func legalPlacementAlternatesPlayersAndIncrementsRevision() throws {
        var engine = try engine(width: 3, height: 3, depth: 1)
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0)))
        #expect(engine.state.nextPlayer == .white)
        _ = try engine.apply(.place(actor: .white, position: GridPosition(x: 2, y: 2, z: 0)))
        #expect(engine.state.nextPlayer == .black)
        #expect(engine.state.revision == 2)
    }

    // MARK: - checked 整数边界

    @Test func rejectsCaptureCounterOverflowAtomically() throws {
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .black),
            ]
        )
        let state = GameState(
            configuration: configuration,
            board: configuration.board,
            nextPlayer: .black,
            phase: .playing,
            capturedByBlack: UInt64.max,
            capturedByWhite: 0,
            revision: 0
        )
        var engine = RuleEngine(state: state)
        expectAtomicRejection(
            &engine,
            .place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)),
            .arithmeticOverflow
        )
    }

    @Test func rejectsRevisionOverflowAtomically() throws {
        let configuration = try GameConfiguration(width: 3, height: 3, depth: 1)
        let state = GameState(
            configuration: configuration,
            board: configuration.board,
            nextPlayer: .black,
            phase: .playing,
            capturedByBlack: 0,
            capturedByWhite: 0,
            revision: UInt64.max
        )
        var engine = RuleEngine(state: state)
        expectAtomicRejection(
            &engine,
            .place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)),
            .arithmeticOverflow
        )
    }
}
