import Testing

@testable import 立体围棋

/// 三维面积计分测试：六向连通空区归属、外表面边界、死棋移除、贴目与半目总分。
struct TerritoryScorerTests {

    /// 直接构造任意棋盘内容；计分输入不要求是合法对局可达局面。
    private func board(
        width: Int,
        height: Int,
        depth: Int,
        _ stones: [GridPosition: Stone] = [:]
    ) throws -> Board {
        var board = try Board(width: width, height: height, depth: depth)
        for (position, stone) in stones {
            board[position] = stone
        }
        return board
    }

    // MARK: - 空区归属

    @Test func regionTouchingOnlyBlackBelongsToBlack() throws {
        let board = try board(
            width: 3, height: 1, depth: 1,
            [
                GridPosition(x: 0, y: 0, z: 0): .black,
                GridPosition(x: 2, y: 0, z: 0): .black,
            ]
        )
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 0)
        #expect(score.blackStones == 2)
        #expect(score.whiteStones == 0)
        #expect(score.blackEmptyPoints == 1)
        #expect(score.whiteEmptyPoints == 0)
        #expect(score.neutralPoints == 0)
        #expect(score.blackScoreHalfPoints == 6)
        #expect(score.whiteScoreHalfPoints == 0)
        #expect(score.outcome == .win(.black))
    }

    @Test func regionTouchingOnlyWhiteBelongsToWhite() throws {
        let board = try board(
            width: 3, height: 1, depth: 1,
            [
                GridPosition(x: 0, y: 0, z: 0): .white,
                GridPosition(x: 2, y: 0, z: 0): .white,
            ]
        )
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 0)
        #expect(score.whiteEmptyPoints == 1)
        #expect(score.whiteScoreHalfPoints == 6)
        #expect(score.blackScoreHalfPoints == 0)
        #expect(score.outcome == .win(.white))
    }

    @Test func regionTouchingBothColorsIsNeutral() throws {
        let board = try board(
            width: 3, height: 1, depth: 1,
            [
                GridPosition(x: 0, y: 0, z: 0): .black,
                GridPosition(x: 2, y: 0, z: 0): .white,
            ]
        )
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 0)
        #expect(score.neutralPoints == 1)
        #expect(score.blackEmptyPoints == 0)
        #expect(score.whiteEmptyPoints == 0)
        #expect(score.blackScoreHalfPoints == 2)
        #expect(score.whiteScoreHalfPoints == 2)
        #expect(score.outcome == .draw)
    }

    @Test func mixedBorderRegionInThreeDimensionsIsNeutral() throws {
        let board = try board(
            width: 2, height: 2, depth: 2,
            [
                GridPosition(x: 0, y: 0, z: 0): .black,
                GridPosition(x: 1, y: 1, z: 1): .white,
            ]
        )
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 13)
        #expect(score.neutralPoints == 6)
        #expect(score.blackScoreHalfPoints == 2)
        #expect(score.whiteScoreHalfPoints == 15)
        #expect(score.outcome == .win(.white))
    }

    @Test func regionTouchingNoStonesIsNeutral() throws {
        let board = try board(width: 2, height: 2, depth: 2)
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 0)
        #expect(score.neutralPoints == 8)
        #expect(score.blackStones == 0)
        #expect(score.whiteStones == 0)
        #expect(score.blackScoreHalfPoints == 0)
        #expect(score.whiteScoreHalfPoints == 0)
        #expect(score.outcome == .draw)
    }

    /// 有限棋盘的外表面是天然边界；空区接触外表面不会把它变成中立。
    @Test func regionTouchingOuterSurfaceKeepsItsOwner() throws {
        let board = try board(
            width: 2, height: 2, depth: 2,
            [GridPosition(x: 0, y: 0, z: 0): .black]
        )
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 0)
        #expect(score.blackEmptyPoints == 7)
        #expect(score.neutralPoints == 0)
        #expect(score.blackScoreHalfPoints == 16)
        #expect(score.outcome == .win(.black))
    }

    @Test func separateRegionsAreScoredIndependently() throws {
        let board = try board(
            width: 5, height: 1, depth: 1,
            [
                GridPosition(x: 1, y: 0, z: 0): .black,
                GridPosition(x: 3, y: 0, z: 0): .white,
            ]
        )
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 0)
        #expect(score.blackEmptyPoints == 1)
        #expect(score.whiteEmptyPoints == 1)
        #expect(score.neutralPoints == 1)
        #expect(score.blackScoreHalfPoints == 4)
        #expect(score.whiteScoreHalfPoints == 4)
        #expect(score.outcome == .draw)
    }

    // MARK: - 死棋移除

    @Test func callerSuppliedDeadStonesAreRemovedBeforeScoring() throws {
        let board = try board(
            width: 3, height: 1, depth: 1,
            [
                GridPosition(x: 0, y: 0, z: 0): .black,
                GridPosition(x: 2, y: 0, z: 0): .white,
            ]
        )
        let score = TerritoryScorer.score(
            board: board,
            removingDeadStones: [GridPosition(x: 2, y: 0, z: 0)],
            komiHalfPoints: 0
        )
        #expect(score.blackStones == 1)
        #expect(score.whiteStones == 0)
        #expect(score.blackEmptyPoints == 2)
        #expect(score.neutralPoints == 0)
        #expect(score.blackScoreHalfPoints == 6)
        #expect(score.whiteScoreHalfPoints == 0)
        #expect(score.outcome == .win(.black))
    }

    @Test func removingNoStonesMatchesPlainScoring() throws {
        let board = try board(
            width: 3, height: 1, depth: 1,
            [GridPosition(x: 0, y: 0, z: 0): .black]
        )
        #expect(
            TerritoryScorer.score(board: board, removingDeadStones: [], komiHalfPoints: 13)
                == TerritoryScorer.score(board: board, komiHalfPoints: 13)
        )
    }

    // MARK: - 贴目与半目总分

    @Test func komiIsAddedToWhiteOnly() throws {
        let board = try board(width: 3, height: 1, depth: 1)
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 13)
        #expect(score.komiHalfPoints == 13)
        #expect(score.blackScoreHalfPoints == 0)
        #expect(score.whiteScoreHalfPoints == 13)
        #expect(score.outcome == .win(.white))
    }

    @Test func halfPointTotalsUseExactIntegerArithmetic() throws {
        let board = try board(
            width: 3, height: 3, depth: 1,
            [
                GridPosition(x: 0, y: 0, z: 0): .black,
                GridPosition(x: 1, y: 0, z: 0): .black,
                GridPosition(x: 2, y: 0, z: 0): .black,
                GridPosition(x: 0, y: 2, z: 0): .white,
                GridPosition(x: 1, y: 2, z: 0): .white,
                GridPosition(x: 2, y: 2, z: 0): .white,
            ]
        )
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 13)
        #expect(score.blackStones == 3)
        #expect(score.whiteStones == 3)
        #expect(score.neutralPoints == 3)
        #expect(score.blackScoreHalfPoints == 6)
        #expect(score.whiteScoreHalfPoints == 19)
        #expect(score.outcome == .win(.white))
    }

    @Test func equalTotalsAreADraw() throws {
        let board = try board(
            width: 4, height: 1, depth: 1,
            [
                GridPosition(x: 0, y: 0, z: 0): .black,
                GridPosition(x: 3, y: 0, z: 0): .white,
            ]
        )
        let score = TerritoryScorer.score(board: board, komiHalfPoints: 0)
        #expect(score.blackScoreHalfPoints == score.whiteScoreHalfPoints)
        #expect(score.outcome == .draw)
    }

    // MARK: - 上界

    @Test func maximumConfiguredScoreFitsInUInt32() throws {
        var board = try Board(width: 19, height: 19, depth: 19)
        for position in board.canonicalPositions {
            board[position] = .black
        }
        let score = TerritoryScorer.score(board: board, komiHalfPoints: UInt16.max)
        #expect(score.blackStones == 6859)
        #expect(score.blackScoreHalfPoints == 13718)
        #expect(score.whiteScoreHalfPoints == UInt32(UInt16.max))
        #expect(score.blackScoreHalfPoints <= TerritoryScorer.maximumScoreHalfPoints)
        #expect(score.whiteScoreHalfPoints <= TerritoryScorer.maximumScoreHalfPoints)
        #expect(TerritoryScorer.maximumScoreHalfPoints < UInt32.max)
    }

    // MARK: - 状态入口

    @Test func gameStateScoresItsOwnBoardAndKomi() throws {
        let configuration = try GameConfiguration(
            width: 3, height: 1, depth: 1,
            komiHalfPoints: 13,
            initialStones: [PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black)]
        )
        let state = GameState(configuration: configuration)
        let score = state.areaScore()
        #expect(score.komiHalfPoints == 13)
        #expect(score.blackScoreHalfPoints == 6)
        #expect(score.whiteScoreHalfPoints == 13)
        #expect(score.outcome == .win(.white))
    }
}
