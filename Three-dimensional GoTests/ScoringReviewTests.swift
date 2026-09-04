import Testing

@testable import Three_dimensional_Go

/// 停着、认输、死棋审核与恢复对局的状态机测试。
///
/// 重点覆盖：只有 `playing` 阶段的 `nextPlayer` 能停着或认输；审核轮次编号的
/// checked 递增；第二份提交前私有死棋提案不得从任何公共表面泄漏；恢复对局的公平轮次。
struct ScoringReviewTests {

    // MARK: - 夹具

    /// 3×3×1 审核夹具：黑一子在 `(0,0,0)`，白一子在 `(2,2,0)`，贴目 13 半目。
    private func reviewFixture(nextPlayer: Stone = .black) throws -> RuleEngine {
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1,
            nextPlayer: nextPlayer,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 2, y: 2, z: 0), stone: .white),
            ]
        )
        return RuleEngine(configuration: configuration)
    }

    /// 让双方各停着一次进入计分审核，并返回本轮 `reviewID`。
    @discardableResult
    private func enterReview(_ engine: inout RuleEngine) throws -> ReviewID {
        let first = engine.state.nextPlayer
        _ = try engine.apply(.pass(actor: first))
        _ = try engine.apply(.pass(actor: first.opponent))
        return try #require(engine.state.currentReviewID)
    }

    private func blackGroup(_ reviewID: ReviewID) -> GroupID {
        GroupID(reviewID: reviewID, color: .black, anchor: GridPosition(x: 0, y: 0, z: 0))
    }

    private func whiteGroup(_ reviewID: ReviewID) -> GroupID {
        GroupID(reviewID: reviewID, color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
    }

    // MARK: - 停着

    @Test func singlePassSwitchesPlayerAndKeepsPlaying() throws {
        var engine = try reviewFixture()
        let transition = try engine.apply(.pass(actor: .black))
        #expect(engine.state.phase == .playing)
        #expect(engine.state.nextPlayer == .white)
        #expect(engine.state.consecutivePasses == 1)
        #expect(engine.state.revision == 1)
        #expect(engine.state.board == engine.state.configuration.board)
        #expect(transition.placedStone == nil)
        #expect(transition.capturedPositions.isEmpty)
        #expect(engine.state.currentReviewID == nil)
    }

    @Test func secondConsecutivePassEntersScoringReview() throws {
        var engine = try reviewFixture()
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.pass(actor: .white))
        #expect(engine.state.phase == .scoringReview)
        #expect(engine.state.consecutivePasses == 2)
        #expect(engine.state.reviewIndex == 1)
        #expect(engine.state.currentReviewID == ReviewID(value: 1))
        #expect(engine.state.nextPlayer == .black)
        #expect(engine.state.revision == 2)
    }

    @Test func legalPlacementResetsConsecutivePasses() throws {
        var engine = try reviewFixture()
        _ = try engine.apply(.pass(actor: .black))
        _ = try engine.apply(.place(actor: .white, position: GridPosition(x: 1, y: 1, z: 0)))
        #expect(engine.state.consecutivePasses == 0)
        #expect(engine.state.phase == .playing)
    }

    @Test func passRejectedForWrongActorOrWrongPhaseAtomically() throws {
        var engine = try reviewFixture()
        expectAtomicRejection(&engine, .pass(actor: .white), .wrongPlayer)
        try enterReview(&engine)
        expectAtomicRejection(&engine, .pass(actor: .black), .wrongPhase)
        expectAtomicRejection(&engine, .pass(actor: .white), .wrongPhase)
    }

    /// 停着豁免提交前的超级劫拒绝，但接受后仍写入完整状态键。
    @Test func passStateIsInsertedIntoSuperkoHistoryAndBlocksLaterRecreation() throws {
        let configuration = try GameConfiguration(
            width: 4, height: 3, depth: 1,
            initialStones: StateDigestTests.koShape(offsetX: 0, capturable: .black)
        )
        var engine = RuleEngine(configuration: configuration)
        let passKey = StateKey(board: configuration.board, nextPlayer: .white)
        #expect(!engine.state.superkoSeen.contains(passKey, digest: StateKeyDigestV1().digest(passKey)))

        _ = try engine.apply(.pass(actor: .black))
        #expect(engine.state.superkoSeen.contains(passKey, digest: StateKeyDigestV1().digest(passKey)))

        _ = try engine.apply(.place(actor: .white, position: GridPosition(x: 1, y: 1, z: 0)))
        expectAtomicRejection(
            &engine, .place(actor: .black, position: GridPosition(x: 2, y: 1, z: 0)), .superko)
    }

    @Test func reviewIndexOverflowRejectsSecondPassAtomically() throws {
        let configuration = try GameConfiguration(width: 3, height: 3, depth: 1)
        let state = GameState(
            configuration: configuration,
            board: configuration.board,
            nextPlayer: .white,
            phase: .playing,
            capturedByBlack: 0,
            capturedByWhite: 0,
            revision: 7,
            consecutivePasses: 1,
            reviewIndex: UInt32.max
        )
        var engine = RuleEngine(state: state)
        expectAtomicRejection(&engine, .pass(actor: .white), .arithmeticOverflow)
    }

    // MARK: - 认输

    @Test func resignFinishesGameAndPreservesEveryOtherField() throws {
        var engine = try reviewFixture()
        _ = try engine.apply(.pass(actor: .black))
        let before = engine.state
        _ = try engine.apply(.resign(actor: .white))
        #expect(engine.state.phase == .finished)
        #expect(engine.state.result == .resignation(winner: .black, loser: .white))
        #expect(engine.state.revision == before.revision + 1)
        #expect(engine.state.board == before.board)
        #expect(engine.state.nextPlayer == before.nextPlayer)
        #expect(engine.state.consecutivePasses == before.consecutivePasses)
        #expect(engine.state.capturedByBlack == before.capturedByBlack)
        #expect(engine.state.capturedByWhite == before.capturedByWhite)
        #expect(engine.state.superkoSeen == before.superkoSeen)
    }

    @Test func resignRejectedForWrongActorOrWrongPhaseAtomically() throws {
        var engine = try reviewFixture()
        expectAtomicRejection(&engine, .resign(actor: .white), .wrongPlayer)
        try enterReview(&engine)
        expectAtomicRejection(&engine, .resign(actor: .black), .wrongPhase)
    }

    // MARK: - 死棋提案的隐藏

    @Test func firstSubmissionIsHiddenFromPublicSurfaces() throws {
        var engine = try reviewFixture()
        let reviewID = try enterReview(&engine)
        let transition = try engine.apply(
            .submitDeadGroups(actor: .black, groups: [whiteGroup(reviewID)]))

        #expect(engine.publicState.deadGroupStatus(for: .black) == .submitted)
        #expect(engine.publicState.deadGroupStatus(for: .white) == .notSubmitted)
        #expect(engine.publicState.result == nil)
        #expect(transition.events == [.deadGroupsSubmitted(actor: .black, revision: 3)])
        #expect(engine.authoritative.deadGroupProposals[.black]?.groups == [whiteGroup(reviewID)])
    }

    @Test func resumeClearsHiddenProposalsWithoutRevealingThem() throws {
        var engine = try reviewFixture()
        let reviewID = try enterReview(&engine)
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [whiteGroup(reviewID)]))
        let transition = try engine.apply(.resume(actor: .white))
        #expect(engine.authoritative.deadGroupProposals.isEmpty)
        #expect(engine.publicState.deadGroupStatus(for: .black) == .notSubmitted)
        #expect(transition.events == [.resumed(actor: .white, nextPlayer: .black, revision: 4)])
    }

    // MARK: - 一致、不一致与提交校验

    @Test func agreementRemovesDeadStonesScoresAndFinishes() throws {
        var engine = try reviewFixture()
        let reviewID = try enterReview(&engine)
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [whiteGroup(reviewID)]))
        let transition = try engine.apply(
            .submitDeadGroups(actor: .white, groups: [whiteGroup(reviewID)]))

        #expect(engine.state.phase == .finished)
        #expect(engine.publicState.deadGroupStatus(for: .black) == .revealed([whiteGroup(reviewID)]))
        #expect(engine.publicState.deadGroupStatus(for: .white) == .revealed([whiteGroup(reviewID)]))
        let result = try #require(engine.state.result)
        guard case let .areaScore(outcome) = result else {
            Issue.record("expected an area score result")
            return
        }
        #expect(outcome.reviewID == reviewID)
        #expect(outcome.agreedDeadGroups == [whiteGroup(reviewID)])
        #expect(outcome.breakdown.blackStones == 1)
        #expect(outcome.breakdown.whiteStones == 0)
        #expect(outcome.breakdown.blackEmptyPoints == 8)
        #expect(outcome.breakdown.blackScoreHalfPoints == 18)
        #expect(outcome.breakdown.whiteScoreHalfPoints == 13)
        #expect(outcome.breakdown.outcome == .win(.black))
        #expect(transition.events.contains(.finished(result: result, revision: 4)))
    }

    @Test func disagreementRevealsBothSetsAndStaysInReview() throws {
        var engine = try reviewFixture()
        let reviewID = try enterReview(&engine)
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [whiteGroup(reviewID)]))
        _ = try engine.apply(.submitDeadGroups(actor: .white, groups: []))

        #expect(engine.state.phase == .scoringReview)
        #expect(engine.state.result == nil)
        #expect(engine.publicState.deadGroupStatus(for: .black) == .revealed([whiteGroup(reviewID)]))
        #expect(engine.publicState.deadGroupStatus(for: .white) == .revealed([]))
        #expect(engine.state.board == engine.state.configuration.board)
    }

    @Test func duplicateSubmissionIsRejectedForEitherColorFirst() throws {
        for first in [Stone.black, Stone.white] {
            var engine = try reviewFixture()
            let reviewID = try enterReview(&engine)
            _ = try engine.apply(.submitDeadGroups(actor: first, groups: [whiteGroup(reviewID)]))
            expectAtomicRejection(
                &engine,
                .submitDeadGroups(actor: first, groups: [blackGroup(reviewID)]),
                .alreadySubmitted(first)
            )
        }
    }

    @Test func staleReviewIDIsRejected() throws {
        var engine = try reviewFixture()
        let firstReview = try enterReview(&engine)
        _ = try engine.apply(.resume(actor: .black))
        let secondReview = try enterReview(&engine)
        #expect(secondReview == ReviewID(value: 2))
        expectAtomicRejection(
            &engine,
            .submitDeadGroups(actor: .black, groups: [whiteGroup(firstReview)]),
            .staleReviewID(firstReview)
        )
    }

    @Test func groupIDMustNameAnExistingGroupByItsLexicographicAnchor() throws {
        let configuration = try GameConfiguration(
            width: 3, height: 3, depth: 1,
            initialStones: [
                PlacedStone(position: GridPosition(x: 0, y: 0, z: 0), stone: .black),
                PlacedStone(position: GridPosition(x: 0, y: 1, z: 0), stone: .black),
            ]
        )
        var engine = RuleEngine(configuration: configuration)
        let reviewID = try enterReview(&engine)

        let emptyAnchor = GroupID(
            reviewID: reviewID, color: .black, anchor: GridPosition(x: 2, y: 2, z: 0))
        expectAtomicRejection(
            &engine, .submitDeadGroups(actor: .black, groups: [emptyAnchor]),
            .invalidDeadGroup(emptyAnchor))

        let wrongColor = GroupID(
            reviewID: reviewID, color: .white, anchor: GridPosition(x: 0, y: 0, z: 0))
        expectAtomicRejection(
            &engine, .submitDeadGroups(actor: .black, groups: [wrongColor]),
            .invalidDeadGroup(wrongColor))

        let nonAnchorMember = GroupID(
            reviewID: reviewID, color: .black, anchor: GridPosition(x: 0, y: 1, z: 0))
        expectAtomicRejection(
            &engine, .submitDeadGroups(actor: .black, groups: [nonAnchorMember]),
            .invalidDeadGroup(nonAnchorMember))

        let anchor = GroupID(
            reviewID: reviewID, color: .black, anchor: GridPosition(x: 0, y: 0, z: 0))
        _ = try engine.apply(.submitDeadGroups(actor: .black, groups: [anchor]))
        #expect(engine.authoritative.deadGroupProposals[.black]?.groups == [anchor])
    }

    @Test func submissionsAreDeduplicatedAndCanonicallySorted() throws {
        var engine = try reviewFixture()
        let reviewID = try enterReview(&engine)
        _ = try engine.apply(
            .submitDeadGroups(
                actor: .black,
                groups: [
                    whiteGroup(reviewID), blackGroup(reviewID), whiteGroup(reviewID),
                ]
            )
        )
        #expect(
            engine.authoritative.deadGroupProposals[.black]?.groups == [
                blackGroup(reviewID), whiteGroup(reviewID),
            ]
        )
        #expect(
            engine.state.log.entries.last?.action
                == .submitDeadGroups(
                    actor: .black, groups: [blackGroup(reviewID), whiteGroup(reviewID)])
        )
    }

    @Test func permutedEquivalentSubmissionsProduceIdenticalLogs() throws {
        var forward = try reviewFixture()
        var reversed = try reviewFixture()
        let reviewID = try enterReview(&forward)
        _ = try enterReview(&reversed)
        _ = try forward.apply(
            .submitDeadGroups(actor: .black, groups: [blackGroup(reviewID), whiteGroup(reviewID)]))
        _ = try reversed.apply(
            .submitDeadGroups(
                actor: .black, groups: [whiteGroup(reviewID), blackGroup(reviewID), blackGroup(reviewID)]))
        #expect(forward.state.log == reversed.state.log)
    }

    @Test func submitRejectedOutsideScoringReviewAtomically() throws {
        var engine = try reviewFixture()
        let group = GroupID(
            reviewID: ReviewID(value: 1), color: .white, anchor: GridPosition(x: 2, y: 2, z: 0))
        expectAtomicRejection(
            &engine, .submitDeadGroups(actor: .black, groups: [group]), .wrongPhase)
    }

    // MARK: - 恢复对局与公平轮次

    /// 两种停着顺序与两种恢复请求方的四种组合都必须给出同一个轮次结果。
    @Test(arguments: [Stone.black, Stone.white], [Stone.black, Stone.white])
    func resumeIsFairForEveryPassOrderAndActor(firstPasser: Stone, resumeActor: Stone) throws {
        var engine = try reviewFixture(nextPlayer: firstPasser)
        let secondPasser = firstPasser.opponent
        try enterReview(&engine)
        let review = engine.state

        _ = try engine.apply(.resume(actor: resumeActor))
        #expect(engine.state.phase == .playing)
        #expect(engine.state.consecutivePasses == 0)
        #expect(engine.state.nextPlayer == secondPasser.opponent)
        #expect(engine.state.nextPlayer == firstPasser)
        #expect(engine.state.reviewIndex == 1)
        #expect(engine.state.currentReviewID == nil)
        #expect(engine.state.board == review.board)
        #expect(engine.state.capturedByBlack == review.capturedByBlack)
        #expect(engine.state.capturedByWhite == review.capturedByWhite)
        #expect(engine.state.superkoSeen == review.superkoSeen)

        _ = try engine.apply(.pass(actor: firstPasser))
        #expect(engine.state.phase == .playing)
        #expect(engine.state.consecutivePasses == 1)

        _ = try engine.apply(.pass(actor: secondPasser))
        #expect(engine.state.phase == .scoringReview)
        #expect(engine.state.reviewIndex == 2)
        #expect(engine.state.currentReviewID == ReviewID(value: 2))

        let replayed = try RuleEngine.replaying(engine.state.log)
        #expect(replayed.state == engine.state)
        #expect(replayed.state.reviewIndex == 2)
        #expect(replayed.state.phase == .scoringReview)
    }

    @Test func resumeRejectedOutsideScoringReviewAtomically() throws {
        var engine = try reviewFixture()
        expectAtomicRejection(&engine, .resume(actor: .black), .wrongPhase)
    }
}
