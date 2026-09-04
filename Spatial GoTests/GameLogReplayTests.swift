import Testing

@testable import SpatialGo

/// 权威日志的创建头、完整落子载荷记录、确定性重放，以及被拒绝落子对日志的零影响。
struct GameLogReplayTests {

    // MARK: - 创建头

    @Test func headerRecordsRulesAndLogFormatVersions() throws {
        let configuration = try GameConfiguration(width: 5, height: 5, depth: 3)
        let engine = RuleEngine(configuration: configuration)
        #expect(engine.state.log.header.rulesVersion == "3d-go/1")
        #expect(engine.state.log.header.logFormatVersion == 1)
        #expect(engine.state.log.header.configuration == configuration)
        #expect(engine.state.log.entries.isEmpty)
    }

    @Test func headerInitialStonesUseCanonicalAnchorOrder() throws {
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 2, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 0, y: 2, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
            ]
        )
        let engine = RuleEngine(configuration: configuration)
        #expect(
            engine.state.log.header.initialStones.map(\.position) == [
                GridPosition(x: 0, y: 0, z: 0),
                GridPosition(x: 0, y: 2, z: 0),
                GridPosition(x: 2, y: 0, z: 0),
            ]
        )
    }

    // MARK: - 完整载荷

    @Test func acceptedPlacementsAreLoggedWithCompletePayload() throws {
        var engine = RuleEngine(configuration: try GameConfiguration(width: 3, height: 3, depth: 2))
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0)))
        _ = try engine.apply(.place(actor: .white, position: GridPosition(x: 2, y: 2, z: 1)))
        #expect(
            engine.state.log.entries == [
                GameLogEntry(
                    revision: 1,
                    action: .place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0))),
                GameLogEntry(
                    revision: 2,
                    action: .place(actor: .white, position: GridPosition(x: 2, y: 2, z: 1))),
            ]
        )
    }

    // MARK: - 被拒绝动作不入日志

    @Test func rejectedPlacementsLeaveTheLogUnchanged() throws {
        var engine = RuleEngine(configuration: try GameConfiguration(width: 3, height: 3, depth: 1))
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        let before = engine.state
        let rejected: [(GameAction, RuleViolation)] = [
            (.place(actor: .black, position: GridPosition(x: 0, y: 0, z: 0)), .wrongPlayer),
            (.place(actor: .white, position: GridPosition(x: 1, y: 1, z: 0)), .occupied),
            (.place(actor: .white, position: GridPosition(x: 9, y: 0, z: 0)), .outOfBounds),
        ]
        for (action, violation) in rejected {
            #expect(throws: violation) { try engine.apply(action) }
            #expect(engine.state == before)
        }
        #expect(engine.state.log.entries.count == 1)
    }

    @Test func rejectedSuperkoRecaptureLeavesTheLogUnchanged() throws {
        var engine = RuleEngine(configuration: try StateDigestTests.singleKoConfiguration())
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        let before = engine.state
        #expect(throws: RuleViolation.superko) {
            try engine.apply(.place(actor: .white, position: GridPosition(x: 2, y: 1, z: 0)))
        }
        #expect(engine.state == before)
        #expect(engine.state.log.entries.count == 1)
    }

    // MARK: - 确定性重放

    @Test func replayReproducesIdenticalState() throws {
        var engine = RuleEngine(configuration: try StateDigestTests.tripleKoConfiguration())
        let moves: [(Stone, GridPosition)] = [
            (.black, GridPosition(x: 1, y: 1, z: 0)),
            (.white, GridPosition(x: 6, y: 1, z: 0)),
            (.black, GridPosition(x: 11, y: 1, z: 0)),
            (.white, GridPosition(x: 2, y: 1, z: 0)),
        ]
        for (actor, position) in moves {
            _ = try engine.apply(.place(actor: actor, position: position))
        }
        let replayed = try RuleEngine.replaying(engine.state.log)
        #expect(replayed.state == engine.state)
        #expect(replayed.state.board == engine.state.board)
        #expect(replayed.state.revision == 4)
        #expect(replayed.state.capturedStones(by: .black) == 2)
        #expect(replayed.state.capturedStones(by: .white) == 2)
        #expect(replayed.state.superkoSeen == engine.state.superkoSeen)
    }

    @Test func replayIsDeterministicAcrossRepeatedRuns() throws {
        var engine = RuleEngine(configuration: try GameConfiguration(width: 4, height: 3, depth: 2))
        let moves: [(Stone, GridPosition)] = [
            (.black, GridPosition(x: 0, y: 0, z: 0)),
            (.white, GridPosition(x: 1, y: 0, z: 0)),
            (.black, GridPosition(x: 0, y: 1, z: 1)),
            (.white, GridPosition(x: 3, y: 2, z: 1)),
        ]
        for (actor, position) in moves {
            _ = try engine.apply(.place(actor: actor, position: position))
        }
        let first = try RuleEngine.replaying(engine.state.log)
        let second = try RuleEngine.replaying(engine.state.log)
        #expect(first.state == second.state)
        #expect(first.state.log == engine.state.log)
    }

    // MARK: - 停着、认输与审核的重放

    @Test func replayReproducesPassCountersAndReviewEntry() throws {
        var engine = RuleEngine(configuration: try GameConfiguration(width: 3, height: 3, depth: 1))
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.pass(actor: .white))
        let replayed = try RuleEngine.replaying(engine.state.log)
        #expect(replayed.state == engine.state)
        #expect(replayed.state.phase == .scoringReview)
        #expect(replayed.state.consecutivePasses == 2)
        #expect(replayed.state.currentReviewID == ReviewID(value: 1))
    }

    @Test func replayReproducesResignation() throws {
        var engine = RuleEngine(configuration: try GameConfiguration(width: 3, height: 3, depth: 1))
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        _ = try engine.apply(.resign(actor: .white))
        let replayed = try RuleEngine.replaying(engine.state.log)
        #expect(replayed.state == engine.state)
        #expect(replayed.state.result == .resignation(winner: .black, loser: .white))
        #expect(replayed.state.phase == .finished)
    }

    @Test func replayReproducesAgreedScoringAndResumePaths() throws {
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 2, y: 2, z: 0), stone: .white),
            ]
        )
        var engine = RuleEngine(configuration: configuration)
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.pass(actor: .white))
        let firstReview = try #require(engine.state.currentReviewID)
        let disputed = GroupID(
            reviewID: firstReview, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [disputed]))
        _ = try engine.apply(.submitDeadGroups(actor: .white, groups: []))
        _ = try engine.apply(.resume(actor: .white))
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.pass(actor: .white))
        let reviewID = try #require(engine.state.currentReviewID)
        let dead = GroupID(reviewID: reviewID, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [dead]))
        _ = try engine.apply(.submitDeadGroups(actor: .white, groups: [dead]))

        let replayed = try RuleEngine.replaying(engine.state.log)
        #expect(replayed.state == engine.state)
        #expect(replayed.state.phase == .finished)
        #expect(replayed.state.reviewIndex == 2)
        #expect(replayed.authoritative == engine.authoritative)
    }

    @Test func rejectedEndgameActionsLeaveTheLogUnchanged() throws {
        var engine = RuleEngine(configuration: try GameConfiguration(width: 3, height: 3, depth: 1))
        _ = try engine.apply(.pass(actor: .black))
        let before = engine.authoritative
        expectAtomicRejection(&engine, .pass(actor: .black), .wrongPlayer)
        expectAtomicRejection(&engine, .resign(actor: .black), .wrongPlayer)
        expectAtomicRejection(&engine, .resume(actor: .white), .wrongPhase)
        #expect(engine.authoritative == before)
        #expect(engine.state.log.entries.count == 1)
    }

    @Test func replayReproducesCapturesAndCaptureCounters() throws {
        var engine = RuleEngine(configuration: try StateDigestTests.singleKoConfiguration())
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 1, y: 1, z: 0)))
        let replayed = try RuleEngine.replaying(engine.state.log)
        #expect(replayed.state.board[GridPosition(x: 2, y: 1, z: 0)] == nil)
        #expect(replayed.state.board[GridPosition(x: 1, y: 1, z: 0)] == .black)
        #expect(replayed.state.capturedStones(by: .black) == 1)
        #expect(replayed.state.nextPlayer == .white)
    }
}
