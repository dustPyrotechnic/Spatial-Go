import Testing

@testable import Three_dimensional_Go

/// 不可变快照、修订号、棋盘摘要与渲染镜像巡检测试。
///
/// 复杂度用注入的访问计数器证明，不使用挂钟时间断言。
struct RenderMirrorTests {

    private func captureFixture() throws -> RuleEngine {
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .white),
                PlacedStone(position: GridPosition(x: 1, y: 0, z: 0), stone: .black),
            ]
        )
        return RuleEngine(configuration: configuration)
    }

    private func reviewFixture() throws -> RuleEngine {
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 2, y: 2, z: 0), stone: .white),
            ]
        )
        return RuleEngine(configuration: configuration)
    }

    // MARK: - 棋盘摘要

    @Test func boardDigestGoldenVectors() throws {
        let single = try Board(width: 1, height: 1, depth: 1)
        #expect(BoardDigestV1().digest(single) == 0x797f_aa7b_e415_2c84)

        var asymmetric = try Board(width: 2, height: 1, depth: 2)
        asymmetric[GridPosition(x: 0, y: 0, z: 0)] = .black
        asymmetric[GridPosition(x: 0, y: 0, z: 1)] = .white
        asymmetric[GridPosition(x: 1, y: 0, z: 1)] = .black
        #expect(BoardDigestV1().digest(asymmetric) == 0x5d23_acc9_42a0_6bac)
    }

    /// 渲染镜像不含下一行棋方，因此棋盘摘要不能复用 ``StateKeyDigestV1``。
    @Test func boardDigestIgnoresNextPlayerUnlikeStateKeyDigest() throws {
        let board = try Board(width: 3, height: 3, depth: 1)
        let boardDigester = BoardDigestV1()
        let stateDigester = StateKeyDigestV1()
        #expect(boardDigester.digest(board) == boardDigester.digest(board))
        #expect(
            stateDigester.digest(StateKey(board: board, nextPlayer: .black))
                != stateDigester.digest(StateKey(board: board, nextPlayer: .white))
        )
        #expect(
            boardDigester.digest(board)
                != stateDigester.digest(StateKey(board: board, nextPlayer: .black))
        )
    }

    // MARK: - 修订号

    @Test func revisionAdvancesOnlyOnAcceptedTransitions() throws {
        var engine = try captureFixture()
        #expect(engine.snapshot.revision == 0)
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)))
        #expect(engine.snapshot.revision == 1)

        let before = engine.snapshot
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 2, y: 2, z: 0)), .wrongPlayer)
        expectAtomicRejection(
            &engine, .place(actor: .white, position: GridPosition(x: 9, y: 9, z: 0)), .outOfBounds)
        #expect(engine.snapshot == before)
        #expect(engine.snapshot.revision == 1)
        #expect(engine.snapshot.boardDigest == before.boardDigest)
    }

    @Test func mirrorOnlyOperationsNeverChangeGameRevision() throws {
        var engine = try captureFixture()
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)))
        let revisionBefore = engine.state.revision

        var mirror = RenderMirror(snapshot: engine.snapshot)
        mirror.rebuild(from: engine.snapshot)
        var counters = ReconciliationCounters()
        _ = mirror.reconcile(with: engine.snapshot, counters: &counters)
        mirror.apply([], from: engine.snapshot)

        #expect(engine.state.revision == revisionBefore)
        #expect(engine.snapshot.revision == revisionBefore)
    }

    // MARK: - 增量

    @Test func transitionDeltasDescribeExactlyTheChangedPoints() throws {
        var engine = try captureFixture()
        let transition = try engine.apply(
            .place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)))
        #expect(
            transition.boardDeltas == [
                BoardDelta(position: GridPosition(x: 0, y: 0, z: 0), stone: nil),
                BoardDelta(position: GridPosition(x: 0, y: 1, z: 0), stone: .black),
            ]
        )
    }

    @Test func metadataOnlyActionsProduceNoBoardDeltas() throws {
        var engine = try reviewFixture()
        #expect(try engine.apply(.pass(actor: .black)).boardDeltas.isEmpty)
        #expect(try engine.apply(.pass(actor: .white)).boardDeltas.isEmpty)
        let reviewID = try #require(engine.state.currentReviewID)
        let dead = GroupID(reviewID: reviewID, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        #expect(try engine.apply(.submitDeadGroups(actor: .black, groups: [dead])).boardDeltas.isEmpty)
        #expect(try engine.apply(.submitDeadGroups(actor: .white, groups: [])).boardDeltas.isEmpty)
        #expect(try engine.apply(.resume(actor: .white)).boardDeltas.isEmpty)
    }

    /// 没有棋盘增量的动作同样会改变公开元数据；镜像必须整体跟随快照，不能假同步。
    @Test func metadataOnlyActionsKeepMirrorInExactSync() throws {
        var engine = try reviewFixture()
        var mirror = RenderMirror(snapshot: engine.snapshot)

        func step(_ action: GameAction, sourceLocation: SourceLocation = #_sourceLocation) throws {
            let transition = try engine.apply(action)
            mirror.apply(transition.boardDeltas, from: engine.snapshot)
            var counters = ReconciliationCounters()
            #expect(mirror.metadata == engine.snapshot.metadata, sourceLocation: sourceLocation)
            #expect(mirror.board == engine.snapshot.board, sourceLocation: sourceLocation)
            #expect(mirror.revision == engine.snapshot.revision, sourceLocation: sourceLocation)
            #expect(mirror.boardDigest == engine.snapshot.boardDigest, sourceLocation: sourceLocation)
            #expect(
                mirror.reconcile(with: engine.snapshot, counters: &counters) == .noChange,
                sourceLocation: sourceLocation
            )
        }

        try step(.pass(actor: .black))
        #expect(mirror.metadata.consecutivePasses == 1)
        #expect(mirror.metadata.phase == .playing)

        try step(.pass(actor: .white))
        #expect(mirror.metadata.phase == .scoringReview)
        #expect(mirror.metadata.reviewID == ReviewID(value: 1))

        let reviewID = try #require(engine.state.currentReviewID)
        let dead = GroupID(reviewID: reviewID, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        try step(.submitDeadGroups(actor: .black, groups: [dead]))
        #expect(mirror.deadGroupStatus(for: .black) == .submitted)
        #expect(mirror.deadGroupStatus(for: .white) == .notSubmitted)

        try step(.submitDeadGroups(actor: .white, groups: []))
        #expect(mirror.deadGroupStatus(for: .black) == .revealed([dead]))
        #expect(mirror.deadGroupStatus(for: .white) == .revealed([]))

        try step(.resume(actor: .black))
        #expect(mirror.metadata.phase == .playing)
        #expect(mirror.metadata.consecutivePasses == 0)
        #expect(mirror.deadGroupStatus(for: .black) == .notSubmitted)
        #expect(mirror.metadata.reviewID == nil)

        try step(.resign(actor: .black))
        #expect(mirror.metadata.phase == .finished)
        #expect(mirror.metadata.result == .resignation(winner: .white, loser: .black))
    }

    /// 元数据漂移不得被宣称为一致，即使棋盘字节完全相同。
    @Test func staleMetadataIsNeverReportedAsNoChange() throws {
        var engine = try reviewFixture()
        let mirror = RenderMirror(snapshot: engine.snapshot)
        _ = try engine.apply(.pass(actor: .black))
        #expect(mirror.board == engine.snapshot.board)
        #expect(mirror.boardDigest == engine.snapshot.boardDigest)

        var counters = ReconciliationCounters()
        #expect(mirror.reconcile(with: engine.snapshot, counters: &counters) != .noChange)
    }

    @Test func rebuildRefreshesEveryPublicField() throws {
        var engine = try reviewFixture()
        var mirror = RenderMirror(snapshot: engine.snapshot)
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.pass(actor: .white))
        let reviewID = try #require(engine.state.currentReviewID)
        let dead = GroupID(reviewID: reviewID, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [dead]))
        _ = try engine.apply(.submitDeadGroups(actor: .white, groups: [dead]))

        mirror.rebuild(from: engine.snapshot)
        #expect(mirror.board == engine.snapshot.board)
        #expect(mirror.revision == engine.snapshot.revision)
        #expect(mirror.boardDigest == engine.snapshot.boardDigest)
        #expect(mirror.metadata == engine.snapshot.metadata)
        #expect(mirror.deadGroupStatus(for: .black) == .revealed([dead]))
        #expect(mirror.metadata.phase == .finished)
        var counters = ReconciliationCounters()
        #expect(mirror.reconcile(with: engine.snapshot, counters: &counters) == .noChange)
        #expect(counters.visitedCells == 0)
    }

    @Test func agreedDeadStoneRemovalIsPublishedAsDeltas() throws {
        var engine = try reviewFixture()
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.pass(actor: .white))
        let reviewID = try #require(engine.state.currentReviewID)
        let dead = GroupID(reviewID: reviewID, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [dead]))
        let transition = try engine.apply(.submitDeadGroups(actor: .white, groups: [dead]))
        #expect(
            transition.boardDeltas == [
                BoardDelta(position: GridPosition(x: 2, y: 2, z: 0), stone: nil)
            ]
        )
    }

    @Test func applyingDeltasKeepsMirrorExactlyEqualToSnapshot() throws {
        var engine = try captureFixture()
        var mirror = RenderMirror(snapshot: engine.snapshot)
        let transition = try engine.apply(
            .place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)))
        mirror.apply(transition.boardDeltas, from: engine.snapshot)

        #expect(mirror.board == engine.snapshot.board)
        #expect(mirror.metadata == engine.snapshot.metadata)
        #expect(mirror.revision == engine.snapshot.revision)
        #expect(mirror.boardDigest == engine.snapshot.boardDigest)

        var counters = ReconciliationCounters()
        #expect(mirror.reconcile(with: engine.snapshot, counters: &counters) == .noChange)
    }

    // MARK: - 巡检复杂度

    @Test func periodicCheckComparesOnlyRevisionAndDigest() throws {
        let engine = try captureFixture()
        let mirror = RenderMirror(snapshot: engine.snapshot)
        var counters = ReconciliationCounters()
        #expect(mirror.reconcile(with: engine.snapshot, counters: &counters) == .noChange)
        #expect(counters.digestComparisons == 1)
        #expect(counters.visitedCells == 0)
        #expect(counters.rebuilds == 0)
    }

    @Test func mismatchedDigestTriggersExactCoordinateDiff() throws {
        var engine = try captureFixture()
        let mirror = RenderMirror(snapshot: engine.snapshot)
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)))

        var counters = ReconciliationCounters()
        let decision = mirror.reconcile(with: engine.snapshot, counters: &counters)
        #expect(
            decision
                == .apply([
                    BoardDelta(position: GridPosition(x: 0, y: 0, z: 0), stone: nil),
                    BoardDelta(position: GridPosition(x: 0, y: 1, z: 0), stone: .black),
                ])
        )
        #expect(counters.digestComparisons == 1)
        #expect(counters.visitedCells == engine.snapshot.board.pointCount)
        #expect(counters.rebuilds == 0)
    }

    @Test func repairedMirrorMatchesSnapshotExactly() throws {
        var engine = try captureFixture()
        var mirror = RenderMirror(snapshot: engine.snapshot)
        _ = try engine.apply(.place(actor: .black, position: GridPosition(x: 0, y: 1, z: 0)))
        var counters = ReconciliationCounters()
        guard case let .apply(deltas) = mirror.reconcile(with: engine.snapshot, counters: &counters)
        else {
            Issue.record("expected a coordinate diff")
            return
        }
        mirror.apply(deltas, from: engine.snapshot)
        #expect(mirror.board == engine.snapshot.board)
        #expect(mirror.boardDigest == engine.snapshot.boardDigest)
        #expect(mirror.metadata == engine.snapshot.metadata)
        var afterRepair = ReconciliationCounters()
        #expect(mirror.reconcile(with: engine.snapshot, counters: &afterRepair) == .noChange)
    }

    // MARK: - 完整重建

    @Test func dimensionMismatchFallsBackToFullRebuild() throws {
        let small = RuleEngine(configuration: try GameConfiguration(width: 3, height: 3, depth: 1))
        let large = RuleEngine(configuration: try GameConfiguration(width: 4, height: 3, depth: 2))
        var mirror = RenderMirror(snapshot: small.snapshot)
        var counters = ReconciliationCounters()
        #expect(mirror.reconcile(with: large.snapshot, counters: &counters) == .rebuild)
        #expect(counters.rebuilds == 1)
        #expect(counters.visitedCells == 0)

        mirror.rebuild(from: large.snapshot)
        #expect(mirror.board == large.snapshot.board)
        #expect(mirror.revision == large.snapshot.revision)
        #expect(mirror.boardDigest == large.snapshot.boardDigest)
        #expect(mirror.metadata == large.snapshot.metadata)
    }

    @Test func damagedMirrorFallsBackToFullRebuild() throws {
        let engine = try captureFixture()
        let mirror = RenderMirror(snapshot: engine.snapshot)
        var counters = ReconciliationCounters()
        #expect(
            mirror.reconcile(with: engine.snapshot, mirrorIsIntact: false, counters: &counters)
                == .rebuild
        )
        #expect(counters.rebuilds == 1)
        #expect(counters.digestComparisons == 0)
    }

    // MARK: - 私有提案脱敏

    @Test func snapshotHidesTheFirstDeadGroupProposal() throws {
        var engine = try reviewFixture()
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.pass(actor: .white))
        let reviewID = try #require(engine.state.currentReviewID)
        let dead = GroupID(reviewID: reviewID, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [dead]))

        let snapshot = engine.snapshot
        #expect(snapshot.deadGroupStatus(for: .black) == .submitted)
        #expect(snapshot.deadGroupStatus(for: .white) == .notSubmitted)
        #expect(snapshot.result == nil)
        #expect(snapshot.phase == .scoringReview)
        #expect(snapshot.reviewID == reviewID)

        _ = try engine.apply(.submitDeadGroups(actor: .white, groups: [dead]))
        #expect(engine.snapshot.deadGroupStatus(for: .black) == .revealed([dead]))
        #expect(engine.snapshot.deadGroupStatus(for: .white) == .revealed([dead]))
        #expect(engine.snapshot.phase == .finished)
    }

    @Test func mirrorNeverCarriesProposalsOrLogs() throws {
        var engine = try reviewFixture()
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.pass(actor: .white))
        let reviewID = try #require(engine.state.currentReviewID)
        let dead = GroupID(reviewID: reviewID, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [dead]))

        let mirror = RenderMirror(snapshot: engine.snapshot)
        #expect(mirror.deadGroupStatus(for: .black) == .submitted)
        #expect(mirror.board == engine.state.board)
        #expect(engine.authoritative.deadGroupProposals[.black]?.groups == [dead])
    }
}
