# Three-dimensional Go Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

If the runner exposes the skill without a vendor namespace, `superpowers:executing-plans` means the available `executing-plans` skill.

**Goal:** Build a testable three-dimensional Go rules engine and an ARKit/RealityKit iOS experience that anchors a configurable full-volume board, selects intersections with a center reticle, and lets one human play both colors while the computer-player seam remains empty.

**Architecture:** `Go3DCore` is a pure Swift source group and the only authority for game state, rules, scoring, logs, revisions, and digests. `GameSession` routes player actions into the core. ARKit/RealityKit project immutable snapshots into an anchored scene through a renderer mirror; event-driven deltas are primary and periodic revision/digest checks only reconcile drift.

**Tech Stack:** Swift, Swift Testing, SwiftUI, ARKit, RealityKit, simd, XCTest UI tests where useful, Instruments and ARKit-capable iPhone/iPad for final acceptance.

---

## Preconditions and execution rules

- Read `docs/plans/2026-09-03-three-dimensional-go-design.md` before changing rules, AR selection, rendering, or synchronization.
- Preserve the existing untracked `Three-dimensional Go.xcodeproj/xcuserdata/` directory.
- Hard gate before Task 1: commit the design, README, AGENTS, and this plan together; require a clean status except explicitly preserved `xcuserdata`; and verify each document with `git show <DOC_COMMIT>:<path>`. Then create the implementation branch/worktree from a commit that contains that exact documentation commit. There is no current-worktree fallback for uncommitted governance documents.
- Run logic tests after every core task. A simulator build does not prove AR placement, tracking, visual correctness, thermal behavior, or reticle usability.
- Keep `Go3DCore` free of `SwiftUI`, `ARKit`, and `RealityKit` imports.
- Use @test-driven-development for behavioral changes, @swiftui-specialist for SwiftUI code, @device-interaction when Xcode MCP is available for simulator/device interaction, and @verification-before-completion before every completion claim.
- Before every task commit, stage only that task's explicit paths, run `git diff --check` and `git diff --cached --check`, and inspect `git status --short`; never stage or delete `Three-dimensional Go.xcodeproj/xcuserdata/`.

## Target source layout

```text
Three-dimensional Go/
├── App/
│   ├── AppModel.swift
│   └── RootView.swift
├── Core/
│   ├── Board.swift
│   ├── GameAction.swift
│   ├── GameConfiguration.swift
│   ├── GameLog.swift
│   ├── GameSnapshot.swift
│   ├── GameState.swift
│   ├── AuthoritativeGameState.swift
│   ├── GridPosition.swift
│   ├── PublicGameEvent.swift
│   ├── PublicGameState.swift
│   ├── RuleEngine.swift
│   ├── StateDigest.swift
│   └── TerritoryScorer.swift
├── Players/
│   ├── ComputerPlayer.swift
│   ├── GameSession.swift
│   ├── GamePlayer.swift
│   ├── HumanPlayer.swift
│   ├── ManualOpponent.swift
│   └── PlayerController.swift
├── AR/
│   ├── ARBoardContainer.swift
│   ├── ARBoardCoordinator.swift
│   ├── ARPlacementView.swift
│   ├── BoardBenchmarkScenario.swift
│   ├── BoardGeometry.swift
│   ├── BoardRenderer.swift
│   ├── CrosshairSelector.swift
│   ├── CameraAuthorizationState.swift
│   ├── CenterReticleView.swift
│   ├── EntityHealthLedger.swift
│   ├── PerformanceSignposts.swift
│   ├── PerformanceHarness.swift
│   ├── PerformanceWorkloads.json
│   ├── PerformanceReticleWorkloads.json
│   ├── ReticleProjectionKernel.swift
│   ├── RenderMirror.swift
│   └── TrackingState.swift
├── Features/
│   ├── Game/GameHUD.swift
│   ├── Game/GameView.swift
│   ├── Game/DeadGroupReviewView.swift
│   ├── Debug/RenderBenchmarkView.swift
│   ├── Setup/GameSetupView.swift
│   └── Tutorial/SurfaceToVolumeTutorial.swift
└── Three_dimensional_GoApp.swift
Three-dimensional GoTests/
├── BoardTests.swift
├── BoardGeometryTests.swift
├── BoardBenchmarkScenarioTests.swift
├── PerformanceWorkloadTests.swift
├── PerformanceReticleWorkloadTests.swift
├── PerformanceExportTests.swift
├── ARGameFlowTests.swift
├── CrosshairSelectorTests.swift
├── DeadGroupSelectionTests.swift
├── EntityHealthLedgerTests.swift
├── GameLogReplayTests.swift
├── PlayerRoutingTests.swift
├── RenderMirrorTests.swift
├── RuleEngineTests.swift
├── ScoringReviewTests.swift
├── SetupFlowTests.swift
├── StateDigestTests.swift
├── TrackingStateTests.swift
└── TerritoryScorerTests.swift
scripts/
├── ThreeDimensionalGo.tracetemplate
└── export-performance-metrics.swift
```

After Task 1 creates the test target, use this exact focused-test form for every RED/GREEN step, replacing only the final suite name listed in that task:

```bash
xcodebuild -project "Three-dimensional Go.xcodeproj" \
  -scheme "Three-dimensional Go" \
  -destination "platform=iOS Simulator,id=$THREED_GO_SIMULATOR_UDID" \
  -only-testing:"Three-dimensional GoTests/BoardTests" \
  test
```

Before running it, set `THREED_GO_SIMULATOR_UDID` to one explicit available simulator UDID. Do not select a destination by a potentially ambiguous device name.

For every behavior task that starts by writing failing tests, immediately run its listed focused suite and record the expected RED caused by the missing behavior. Implement only after that RED, then run the same command and record GREEN. Compilation errors caused by a broken test target do not count as behavioral RED.

### Task 1: Establish the test target and core value types

**Files:**

- Create: `Three-dimensional Go/Core/GridPosition.swift`
- Create: `Three-dimensional Go/Core/GameConfiguration.swift`
- Create: `Three-dimensional Go/Core/Board.swift`
- Create: `Three-dimensional GoTests/BoardTests.swift`
- Modify: `Three-dimensional Go.xcodeproj/project.pbxproj`
- Create: `Three-dimensional Go.xcodeproj/xcshareddata/xcschemes/Three-dimensional Go.xcscheme`

**Steps:**

1. In Xcode, add an iOS Unit Test target named `Three-dimensional GoTests` using Swift Testing; do not hand-edit unrelated project settings. Share the `Three-dimensional Go` scheme, add the test target to its TestAction, and commit the shared scheme.
2. Write failing tests for dimension bounds, zero-based coordinate validation, linear index round trips, canonical z/y/x traversal, initial-stone validation, and the `1×1×1` boundary.
3. Run the selected `BoardTests`; confirm failures are caused by missing types, not target configuration.
4. Implement minimal value types. Use fixed-width/sendable/hashable values and an internal contiguous `[Stone?]` board representation.

```swift
struct GridPosition: Hashable, Codable, Sendable {
    let x: Int
    let y: Int
    let z: Int
}

enum Stone: UInt8, Codable, Sendable {
    case black = 1
    case white = 2

    var opponent: Stone { self == .black ? .white : .black }
}
```

5. Run `BoardTests` GREEN and the app build, then commit only Task 1 files: `feat: add three-dimensional board model`.
6. After committing, create a detached worktree from that exact commit under a fresh `/tmp/three-d-go-scheme.*` directory. Confirm it contains no `xcuserdata`, then rerun `xcodebuild -list`, focused `BoardTests`, and the app build there using the committed shared scheme. Remove only that validated temporary worktree afterward. Task 1 is incomplete if this clean-worktree audit fails.

### Task 2: Implement groups, liberties, captures, and suicide atomically

**Files:**

- Create: `Three-dimensional Go/Core/GameAction.swift`
- Create: `Three-dimensional Go/Core/GameState.swift`
- Create: `Three-dimensional Go/Core/RuleEngine.swift`
- Create: `Three-dimensional GoTests/RuleEngineTests.swift`

**Steps:**

1. Write failing tests for center/surface/edge/corner neighbor counts, connected groups, distinct liberties, single capture, simultaneous multi-group capture, capture-created liberty, suicide, occupied points, out-of-range points, and wrong actor.
2. Add an atomicity assertion helper that compares the complete pre/post state after every rejected action.
3. Run the focused tests and confirm RED.
4. Implement iterative group traversal and a copy-validate-commit placement transaction. Collect adjacent enemy groups by canonical anchor before removing any group.

```swift
enum RuleViolation: Error, Equatable {
    case wrongPhase, wrongPlayer, outOfBounds, occupied
    case suicide, superko, arithmeticOverflow
}

mutating func apply(_ action: GameAction) throws -> GameTransition
```

5. Count captured enemy stones for the acting player with checked `UInt64` addition. `arithmeticOverflow` is limited to failed checked integer operations; test each reachable counter/revision boundary with an injected near-maximum state. It is not a generic memory or implementation-capacity error.
6. Run focused tests, then all core tests.
7. Commit: `feat: implement atomic placement and capture rules`.

### Task 3: Add deterministic state keys, situational superko, and authoritative logs

**Files:**

- Create: `Three-dimensional Go/Core/GameLog.swift`
- Create: `Three-dimensional Go/Core/StateDigest.swift`
- Create: `Three-dimensional GoTests/StateDigestTests.swift`
- Create: `Three-dimensional GoTests/GameLogReplayTests.swift`
- Modify: `Three-dimensional Go/Core/RuleEngine.swift`

**Steps:**

1. Write failing tests proving canonical z/y/x serialization, initial-state inclusion, immediate ko rejection, longer repeated-state rejection, injected digest-collision exact comparison, and rejected-Place log immutability. Pass and other action types belong to Task 5.
2. Immediately run focused `StateDigestTests` and `GameLogReplayTests`; record behavioral RED for missing canonical digest/superko/replay behavior before defining production log or digest types.
3. Define the log header with `rulesVersion = "3d-go/1"`, `logFormatVersion = 1`, configuration, and canonically sorted initial stones.
4. Implement structured `StateKey`. Define `StateKeyDigestV1` as FNV-1a 64 over ASCII `3dgo-state-v1\0`, three one-byte dimensions, canonical board bytes (`empty=0`, `black=1`, `white=2`), then `nextPlayer` (`black=1`, `white=2`). Compare the full key after a digest hit.
5. Add golden vectors: empty `1×1×1` with black next is `0x3869cb0b3026d098`; with white next it is `0x3869ce0b3026d5b1`. Add a non-symmetric `2×1×2` board whose canonical bytes are `[black, empty, white, black]`: black-next digest `0x3e777dc6ce29d07e`, white-next digest `0x3e777cc6ce29cecb`. Inject a constant-digest implementation to prove collisions cannot reject unequal states.
6. Record and replay the complete accepted `place(actor:position:)` payload. Task 5 extends the same log with Pass, Resign, dead-group submission, and Resume after those actions exist.
7. Re-run the same focused suites GREEN, then all core tests.
8. Commit: `feat: add superko and deterministic game logs`.

### Task 4: Implement three-dimensional area scoring

**Files:**

- Create: `Three-dimensional Go/Core/TerritoryScorer.swift`
- Create: `Three-dimensional GoTests/TerritoryScorerTests.swift`
- Modify: `Three-dimensional Go/Core/GameState.swift`

**Steps:**

1. Define only pure scoring values in this task: `AreaScoreBreakdown` contains stone counts, owned empty counts, neutral count, komi, both half-point totals, and winner/draw. `ReviewID`, `GroupID`, agreed-dead metadata, and final `GameResult` are Task 5 types.
2. Write failing tests for black territory, white territory, mixed-border neutral regions, regions touching no stones, regions touching the outer board surface, a board after caller-supplied dead-stone removal, komi, exact half-point totals, and draw.
3. Run focused `TerritoryScorerTests` and confirm RED.
4. Implement iterative six-direction flood fill and return `AreaScoreBreakdown` only.
5. Assert the maximum configured score fits `UInt32`.
6. Run the same suite GREEN, then all core tests.
7. Commit: `feat: score enclosed three-dimensional regions`.

### Task 5: Implement Pass, resignation, scoring review, and Resume

**Files:**

- Modify: `Three-dimensional Go/Core/GameAction.swift`
- Modify: `Three-dimensional Go/Core/GameState.swift`
- Modify: `Three-dimensional Go/Core/RuleEngine.swift`
- Modify: `Three-dimensional Go/Core/GameLog.swift`
- Create: `Three-dimensional Go/Core/AuthoritativeGameState.swift`
- Create: `Three-dimensional Go/Core/PublicGameState.swift`
- Create: `Three-dimensional Go/Core/PublicGameEvent.swift`
- Create: `Three-dimensional GoTests/ScoringReviewTests.swift`
- Modify: `Three-dimensional GoTests/GameLogReplayTests.swift`

**Steps:**

1. Write failing tests for one/two passes; only `playing.nextPlayer` may Pass, while wrong actor/wrong phase is atomically rejected with private/public state, history, counters, revision, and logs unchanged; Pass-result insertion into `superkoSeen`; a later Place rejected for recreating that state; exact resignation invariants and deterministic Resign replay; group IDs, normalization, duplicate/stale IDs, hidden proposals, agreement, disagreement, and Resume. Add black-first and white-first duplicate-submission cases. Lock review lifecycle: initial `reviewIndex=0`; a successful second consecutive Pass performs checked `+1` and uses the result as `reviewID`; overflow rejects atomically; Resume never increments; IDs are unusable outside their active review; the next successful second Pass increments again. A successful Resign increments revision, preserves board/nextPlayer/captures/superko/consecutivePasses, and creates `GameResult.resignation(winner:loser:)`; wrong actor or phase is atomically rejected.
2. Add four fairness regressions: both Pass orders crossed with black and white as the Resume actor. Either color may request Resume, actor never changes the chosen turn, and `nextPlayer` remains the opponent of the second passer. A successful Resume atomically sets `consecutivePasses=0` while preserving board, captured-stone counts, and superko history. For all four cases, the first new Pass remains `playing`; only the second new Pass enters a review with `reviewIndex+1`. Replay must reproduce the same counter and phase.
3. Immediately run focused `ScoringReviewTests` and `GameLogReplayTests`; record behavioral RED for missing Pass/review/resignation/replay behavior. Only then define `ReviewID`, `GroupID`, `GameResult.areaScore`, `GameResult.resignation(winner:loser:)`, and the public/private DTOs. Model private authoritative state separately; before both submissions, public output exposes only submitted/not-submitted status.
4. Make the second submission, comparison, reveal, dead-stone removal, Task 4 `AreaScoreBreakdown`, final `GameResult.areaScore` composition, and phase transition one atomic transaction.
5. Preserve the fixed review snapshot. Use `(reviewID, color, anchor)` as `GroupID`, where anchor is the actual group position with lexicographic minimum x, then y, then z; do not use canonical board serialization order here.
6. Extend authoritative logging and replay with complete Pass, Resign, SubmitDeadGroups, and Resume payloads. Persist dead-group submissions only after validation/deduplication and canonical `GroupID` sorting; assert byte-identical logs for permuted equivalent inputs. Assert replay equality for agreement, Resume, and resignation paths.
7. Re-run the same focused suites GREEN, then all core tests.
8. Commit: `feat: add deterministic endgame review state machine`.

### Task 6: Add immutable snapshots, revisions, and render reconciliation data

**Files:**

- Create: `Three-dimensional Go/Core/GameSnapshot.swift`
- Modify: `Three-dimensional Go/Core/AuthoritativeGameState.swift`
- Modify: `Three-dimensional Go/Core/StateDigest.swift`
- Create: `Three-dimensional Go/AR/RenderMirror.swift`
- Create: `Three-dimensional GoTests/RenderMirrorTests.swift`
- Modify: `Three-dimensional Go/Core/RuleEngine.swift`

**Steps:**

1. Write failing tests for revision increments on accepted transitions only, deterministic board digest, delta operation counts, exact mirror equality, coordinate diff, full rebuild fallback, and redaction of private proposal data. Prove complexity with injected visitation counters rather than wall-clock assertions.
2. Immediately run focused `RenderMirrorTests`; record behavioral RED for missing revision/digest/reconciliation/redaction behavior before defining production snapshots or mirror types.
3. Define `AuthoritativeGameState` as private engine/persistence state containing proposal IDs and the full log. Define `GameSnapshot` as a public render-safe snapshot containing board, public phase/status, revision, and board digest only. UI, players, AR, observation history, and restoration surfaces receive `PublicGameState`, `PublicGameEvent`, or render-safe `GameSnapshot`; none can access a first proposal's IDs.
4. Define `BoardDigestV1` as FNV-1a 64 over ASCII `3dgo-board-v1\0`, three one-byte dimensions, and canonical z/y/x board bytes (`empty=0`, `black=1`, `white=2`). Golden values: empty `1×1×1` is `0x797faa7be4152c84`; non-symmetric `2×1×2` bytes `[black, empty, white, black]` produce `0x5d23acc942a06bac`. Do not reuse the StateKey digest because the render mirror excludes `nextPlayer`.
5. Implement reconciliation policy:

```swift
enum ReconciliationDecision: Equatable {
    case noChange
    case apply([BoardDelta])
    case rebuild
}
```

6. Prove rejected actions and AR-only operations do not increment the game revision.
7. Re-run `RenderMirrorTests` GREEN, then all logic tests.
8. Commit: `feat: add snapshot revision and render reconciliation`.

### Task 7: Add player seams and manual two-color control

**Files:**

- Create: `Three-dimensional Go/Players/GamePlayer.swift`
- Create: `Three-dimensional Go/Players/GameSession.swift`
- Create: `Three-dimensional Go/Players/HumanPlayer.swift`
- Create: `Three-dimensional Go/Players/ManualOpponent.swift`
- Create: `Three-dimensional Go/Players/ComputerPlayer.swift`
- Create: `Three-dimensional Go/Players/PlayerController.swift`
- Create: `Three-dimensional Go/App/AppModel.swift`
- Create: `Three-dimensional GoTests/PlayerRoutingTests.swift`

**Steps:**

1. Write failing tests that `GameSession` owns the engine, every player sends the same typed action, actor identity is preserved, manual control can act only for `nextPlayer`, and public state/events are emitted only after accepted transitions.
2. Immediately run focused `PlayerRoutingTests`; record behavioral RED for missing ownership/routing/publication behavior before creating production player/session types.
3. Implement `GameSession` as the sole action router and snapshot publisher. `PlayerController` coordinates the current `GamePlayer`; `HumanPlayer` represents direct interaction and `ManualOpponent` lets the same person supply the opposite side's next legal action.
4. Define a narrow player boundary:

```swift
protocol GamePlayer: Sendable {
    func action(for state: PublicGameState) async -> GameAction?
}

struct ComputerPlayer: GamePlayer {
    func action(for state: PublicGameState) async -> GameAction? { nil }
}
```

5. Keep `ComputerPlayer` intentionally empty and label it as unimplemented in UI/docs.
6. Re-run `PlayerRoutingTests` GREEN, then all core tests.
7. Commit: `feat: add manual opponent and computer player seam`.

### Task 8: Build setup and single-layer-to-volume tutorial UI

**Files:**

- Create: `Three-dimensional Go/App/RootView.swift`
- Create: `Three-dimensional Go/Features/Setup/GameSetupView.swift`
- Create: `Three-dimensional Go/Features/Tutorial/SurfaceToVolumeTutorial.swift`
- Create: `Three-dimensional GoTests/SetupFlowTests.swift`
- Modify: `Three-dimensional Go/ContentView.swift`
- Modify: `Three-dimensional Go/Three_dimensional_GoApp.swift`

**Steps:**

1. With @swiftui-specialist, write failing `SetupFlowTests` for configuration validation, tutorial-to-new-game transition, and the rule that an active game's dimensions never mutate.
2. Run focused `SetupFlowTests` with the shared scheme and confirm behavioral RED before creating the UI.
3. Build controls for width, height, depth, and komi; expose presets without making them hard constraints.
4. Build the tutorial as a presentation transition from one plane to copied vertical layers. Start a new configured game after animation; never mutate active-game dimensions.
5. Add accessibility labels/values, a logical VoiceOver focus order, Dynamic Type layouts through accessibility sizes, and sufficient text/control contrast. Under Reduce Motion, replace copied-layer travel with a non-spatial cross-fade plus an explicit layer-count announcement. Add testable environment seams and assertions for the alternate path; inspect VoiceOver focus, largest text size, contrast, and Reduce Motion on Simulator/device before claiming this task complete.
6. Run the same focused suite GREEN, then the full affected suite and generic Simulator build; retain the accessibility inspection checklist with task evidence.
7. Commit: `feat: add board setup and volume tutorial`.

### Task 9: Establish AR session, horizontal-plane preview, and anchoring

**Files:**

- Create: `Three-dimensional Go/AR/ARBoardContainer.swift`
- Create: `Three-dimensional Go/AR/ARBoardCoordinator.swift`
- Create: `Three-dimensional Go/AR/TrackingState.swift`
- Create: `Three-dimensional Go/AR/ARPlacementView.swift`
- Create: `Three-dimensional Go/AR/CameraAuthorizationState.swift`
- Create: `Three-dimensional Go/AR/CenterReticleView.swift`
- Create: `Three-dimensional GoTests/TrackingStateTests.swift`
- Modify: `Three-dimensional Go/App/RootView.swift`
- Modify: `Three-dimensional Go/App/AppModel.swift`
- Modify: `Three-dimensional Go.xcodeproj/project.pbxproj`

**Steps:**

1. Write failing `TrackingStateTests` for orthogonal placement/tracking state, interruption, recovery, reposition, and camera authorization `.notDetermined/.authorized/.denied/.restricted`; run the focused suite and confirm RED before implementing AR state.
2. Add a camera usage description with user-facing AR purpose text.
3. Implement authorization handling before creating `ARView`: request only from notDetermined; start AR only when authorized; denied/restricted shows an explanation and system Settings action, with no session, anchor, placement action, or rule action. Wrap `ARView` for SwiftUI and configure horizontal plane detection. Model placement lifecycle and tracking quality separately.
4. Raycast only against detected horizontal planes. A valid center hit drives a translucent footprint; confirmation creates one board anchor.
5. Disable rule actions during limited/unavailable tracking. Reposition replaces presentation anchors only.
6. Add `ARPlacementView` and a reachable route from `RootView`. Overlay a fixed hit-test-transparent `CenterReticleView`: neutral while scanning, valid when a plane candidate exists, disabled when authorization/tracking blocks placement. Expose those states as VoiceOver label/value, move accessibility focus to the denial explanation when authorization fails, keep the Settings action reachable, and use shape plus text—not color alone—to distinguish states with sufficient contrast. Reduce Motion removes pulsing/position-travel while preserving state feedback. Add screenshot/device and accessibility checks for all three appearances.
7. Run the same `TrackingStateTests` GREEN and a simulator build; record that simulator cannot validate AR behavior.
8. On an ARKit-capable device, capture evidence for scan, preview, anchor stability, tracking interruption, recovery, and reposition.
9. Commit: `feat: anchor the board on detected horizontal surfaces`.

### Task 10: Generate full board geometry with scalable batching

**Files:**

- Create: `Three-dimensional Go/AR/BoardGeometry.swift`
- Create: `Three-dimensional Go/AR/BoardRenderer.swift`
- Create: `Three-dimensional Go/AR/BoardBenchmarkScenario.swift`
- Create: `Three-dimensional Go/AR/PerformanceSignposts.swift`
- Create: `Three-dimensional Go/AR/PerformanceHarness.swift`
- Create: `Three-dimensional Go/AR/PerformanceWorkloads.json`
- Create: `Three-dimensional Go/AR/PerformanceReticleWorkloads.json`
- Create: `Three-dimensional Go/AR/ReticleProjectionKernel.swift`
- Create: `Three-dimensional Go/Features/Debug/RenderBenchmarkView.swift`
- Create: `Three-dimensional GoTests/BoardGeometryTests.swift`
- Create: `Three-dimensional GoTests/BoardBenchmarkScenarioTests.swift`
- Create: `Three-dimensional GoTests/PerformanceWorkloadTests.swift`
- Create: `Three-dimensional GoTests/PerformanceReticleWorkloadTests.swift`
- Create: `Three-dimensional GoTests/PerformanceExportTests.swift`
- Create: `scripts/ThreeDimensionalGo.tracetemplate`
- Create: `scripts/export-performance-metrics.swift`
- Create: `docs/verification/render-batching-baseline.md`
- Modify: `Three-dimensional Go/AR/ARPlacementView.swift`
- Modify: `Three-dimensional Go/App/RootView.swift`

**Steps:**

1. Write failing tests for logical-to-local mapping, centered extents, `depth=1`, configurable spacing, line-count formula, scaling invariance, chunk membership, exact benchmark fixtures, deterministic move-workload generation, reticle projection/workload validation, and trace-export fixtures. The reticle tests require a pure SIMD kernel; exporter tests cover ordering, duplicates, missing endpoints, digest mismatch, FPS, percentiles, and memory samples.
2. Run focused `BoardGeometryTests`, `BoardBenchmarkScenarioTests`, `PerformanceWorkloadTests`, `PerformanceReticleWorkloadTests`, and `PerformanceExportTests`; record behavioral RED for the missing production geometry, fixtures, kernel, workloads, and exporter before creating them.
3. Implement stable fixtures in `BoardBenchmarkScenario`: `empty-v1` has 0 stones; `checker-half-v1` occupies `(x+y+z)%2==0` and colors by `(x/2+y/2+z/2)%2`, totaling 3,430 stones; `split-dense-v1` has black at `x<9`, empty at `x==9`, white at `x>9`, totaling 6,498 stones.
4. Generate 100 independent move samples per fixture in `PerformanceWorkloads.json`. For sample `i`, reset to the exact fixture with black as `nextPlayer`; start the legal-move scan at `(i × 67) mod 6859` in canonical z/y/x order, wrap once, and select the first Place accepted by `RuleEngine`. Store fixture ID, sample ID, actor, position, `BoardDigestV1` pre-digest, and `BoardDigestV1` post-digest. Tests regenerate all 300 entries, require every action accepted, compare every field, and lock the file SHA-256.
5. Implement the pure SIMD-only `ReticleProjectionKernel`; Task 11's `CrosshairSelector` must delegate its ranking math to this kernel. Generate `reticle-v1` in `PerformanceReticleWorkloads.json` with 100 samples for each of `empty-v1`, `checker-half-v1`, and `split-dense-v1` (300 total). Every sample independently resets its named fixture and stores `fixtureID`, `sampleID`, that fixture's `BoardDigestV1` preDigest, board local transform identity, uniform scale `1.0`, spacing `0.02 m`, an exact column-major 4×4 camera transform, monotonically increasing input timestamp at 50 ms spacing within the fixture, and `expectedCandidate` or explicit `noCandidate` after occupied-point filtering. Tests decode every finite matrix, recompute the expected result through the kernel with the fixture's occupancy, verify counts/order/timing/digest, and lock the file SHA-256.
6. Generate grid lines as one or a few meshes, not one entity per segment. Share stone mesh/material resources and start with a conservative documented batching threshold.
7. Create `PerformanceSignposts` with subsystem `com.xiaochenstudio.Three-dimensional-Go.performance`, category `ARPipeline`, and one monotonic signpost clock. `frame.present` is a timestamp-only instant event carrying fixture/run labels and a monotonically increasing frame sequence; it never has begin/end. Duration intervals are `mesh.generate`, `chunk.rebuild`, `reticle.update`, `move.render`, `audit.array`, `audit.entity`, `repair.targeted`, and `scene.rebuild`; correlate their begin/end by sample ID and include fixture ID, run ID, sample ID, revision, `BoardDigestV1` preDigest, and `BoardDigestV1` postDigest where applicable. `PerformanceHarness` drives committed move/reticle samples and records `CADisplayLink` presentation timestamps as instant `frame.present` events; Task 10 instruments this event plus `mesh.generate` and `chunk.rebuild`.
8. Commit a project-owned `ThreeDimensionalGo.tracetemplate` containing Points of Interest plus process memory sampling. The canonical capture command is `xcrun xctrace record --template scripts/ThreeDimensionalGo.tracetemplate --device "$THREED_GO_DEVICE_UDID" --output "$THREED_GO_TRACE_ROOT/<fixture>-<run>.trace" --launch -- "<built-app-path>" --benchmark <fixture> <run>`. The harness exits only after the fixed warm-up/workload duration and writes its run metadata.
9. Implement `export-performance-metrics.swift` to invoke/consume `xcrun xctrace export --input <trace> --xpath <versioned-export-xpath>`, derive FPS solely from adjacent valid instant `frame.present` timestamps, derive interval durations only from canonical begin/end pairs, and export the fixed Task 14 CSV schema. `PerformanceExportTests` separately test instant-event and interval validity. Lock the XPath/schema version in source.
10. Add a reachable `RenderBenchmarkView` using stable fixtures/workloads and a per-stone/chunked toggle. Measure both paths in Release on the baseline device for 30 seconds after 10 seconds warm-up; record device/OS/build, p5 FPS, memory, mesh-build time, and the selected threshold in `render-batching-baseline.md`.
11. Keep candidate, last move, and animated stones separate from batch meshes. Disable per-stone real-time shadows by default and avoid transparent bulk stones.
12. Re-run all five focused suites GREEN, then the app build; inspect small and `19³` fixtures through the benchmark route.
13. Commit: `feat: render configurable full-volume boards`.

### Task 11: Implement center-reticle selection and confirmation

**Files:**

- Create: `Three-dimensional Go/AR/CrosshairSelector.swift`
- Create: `Three-dimensional GoTests/CrosshairSelectorTests.swift`
- Create: `Three-dimensional GoTests/ARGameFlowTests.swift`
- Create: `Three-dimensional Go/Features/Game/GameHUD.swift`
- Create: `Three-dimensional Go/Features/Game/GameView.swift`
- Modify: `Three-dimensional Go/App/RootView.swift`
- Modify: `Three-dimensional Go/App/AppModel.swift`
- Modify: `Three-dimensional Go/AR/ARPlacementView.swift`
- Modify: `Three-dimensional Go/AR/ARBoardCoordinator.swift`
- Modify: `Three-dimensional Go/AR/BoardRenderer.swift`
- Modify: `Three-dimensional Go/AR/PerformanceSignposts.swift`

**Steps:**

1. Write failing tests for camera-ray transformation, points behind the camera, occupied-point filtering, tolerance, projection-distance ranking, depth tie-break, no candidate, and scaling. Add injectable flow fakes for coordinator, selector, renderer, and session; test `RootView → placement → anchored GameView`, camera update→selector→halo, accepted action→stone delta, and rejected action→no entity mutation.
2. Run `CrosshairSelectorTests` and `ARGameFlowTests`; confirm RED before wiring production types.
3. Store candidate points in a contiguous SIMD buffer. Recompute at 20–30 Hz only after camera/board movement exceeds a threshold.
4. Route camera-frame/board-transform changes from coordinator into selector, then send the coordinate to renderer for halo commit. Instrument pose-change→halo-commit with the shared clock and fixture label.
5. Connect `RootView → ARPlacementView → anchored GameView`; retain the anchor/coordinator so GameView is reachable and receives camera updates.
6. Reuse the hit-test-transparent center reticle in `GameView`: neutral without candidate, valid with candidate, disabled when tracking blocks input. Render one candidate halo and display coordinate, layer, and next player. Announce candidate coordinate/state changes without flooding VoiceOver, expose the confirmation action independently of tap-anywhere, preserve logical focus order at all Dynamic Type sizes, and distinguish the halo by shape/label as well as contrast. Reduce Motion disables halo pulse and animated camera-linked travel.
7. Make tap-anywhere confirm through `GameSession`; instrument accepted-transition→render-delta commit. Rejected actions never mutate entities.
8. Add bounded pinch scaling and no rotation gesture.
9. Run both focused suites GREEN, simulator build, then device acceptance including reticle screenshots, parallax selection, dense-board zoom, VoiceOver confirmation/focus, accessibility text sizes, contrast, and Reduce Motion.
10. Commit: `feat: add center-reticle three-dimensional placement`.

### Task 12: Connect HUD, endgame review, and error presentation

**Files:**

- Modify: `Three-dimensional Go/Features/Game/GameHUD.swift`
- Modify: `Three-dimensional Go/Features/Game/GameView.swift`
- Create: `Three-dimensional Go/Features/Game/DeadGroupReviewView.swift`
- Create: `Three-dimensional GoTests/DeadGroupSelectionTests.swift`
- Modify: `Three-dimensional Go/AR/CrosshairSelector.swift`
- Modify: `Three-dimensional GoTests/CrosshairSelectorTests.swift`
- Modify: `Three-dimensional Go/App/AppModel.swift`

**Steps:**

1. Before implementation, write failing tests for occupied-stone→whole GroupID selection, toggling, stale groups, local-state clearing, automatic turns, Pass, resignation confirmation, first-proposal redaction, opaque handoff, second proposal, disagreement, Resume, and final score UI state.
2. Run `DeadGroupSelectionTests`, `ScoringReviewTests`, `GameLogReplayTests`, `PlayerRoutingTests`, `ARGameFlowTests`, and `CrosshairSelectorTests`; confirm behavioral RED in the suites covering newly missing behavior.
3. Map stable rule violations to concise user messages; keep AR tracking errors separate from rule errors.
4. Generalize crosshair selection for legal empty play points or occupied review groups. Highlight every stone in the selected fixed-snapshot group.
5. Implement first submission, local clearing, opaque handoff, independent second submission, reveal, Resume, and final score. Give whole-group highlights and selected state accessible labels/values; make Pass/resign/handoff actions explicit; move focus to the handoff shield and then the second-player heading; support accessibility Dynamic Type without hiding actions; use sufficient non-color-only state cues; replace board/highlight transitions with cross-fades under Reduce Motion.
6. Ensure the first proposal cannot be recovered from public view state, history, accessibility text, or retained local selection.
7. Verify `ComputerPlayer` is visibly unavailable rather than impersonated by manual control.
8. Re-run all six named suites GREEN and inspect the full simulator flow excluding real AR assertions. Verify VoiceOver privacy/focus, accessibility text sizes, contrast, and Reduce Motion before completing this task.
9. Commit: `feat: complete manual game and scoring UI`.

### Task 13: Activate periodic reconciliation and lifecycle repair

**Files:**

- Modify: `Three-dimensional Go/AR/BoardRenderer.swift`
- Modify: `Three-dimensional Go/AR/ARBoardCoordinator.swift`
- Modify: `Three-dimensional Go/AR/RenderMirror.swift`
- Create: `Three-dimensional Go/AR/EntityHealthLedger.swift`
- Modify: `Three-dimensional GoTests/RenderMirrorTests.swift`
- Create: `Three-dimensional GoTests/EntityHealthLedgerTests.swift`
- Modify: `Three-dimensional Go/AR/PerformanceSignposts.swift`
- Modify: `Three-dimensional Go/App/AppModel.swift`
- Modify: `Three-dimensional Go/Features/Debug/RenderBenchmarkView.swift`
- Create: `Three-dimensional Go/Features/Debug/ReconciliationFaultPanel.swift`

**Steps:**

1. Write failing tests for constant-time revision/digest checks, lifecycle-triggered compact-array diff, targeted chunk repair, severe-mismatch rebuild, constant-digest collision, and entity-ledger corruption. Use visitation counters to prove the fast path never scans board entries or entities.
2. Run focused `RenderMirrorTests` and `EntityHealthLedgerTests` with the shared scheme and confirm RED before changing reconciliation code.
3. Apply action deltas immediately after accepted transitions.
4. While active, compare revision/digest every 2–3 seconds as an O(1) fast signal; matching digests are not proof of equal board contents.
5. On foreground return, tracking recovery, and anchor recreation, compare compact arrays and repair from `GameSnapshot`.
6. Define the guarantee precisely: the O(1) timer repairs mirror/event drift only. Inject faults by changing the mirror alongside the rendered chunk, then prove digest mismatch triggers repair.
7. Add a low-frequency exact compact-array audit every 30 seconds while active and idle enough to run; inject a constant BoardDigest to prove it detects digest collisions. This O(6,859) path is separate from the 2–3 second fast signal.
8. Entity-only corruption cannot be detected from matching core/mirror arrays. Add `EntityHealthLedger` and audit it on foreground return, tracking recovery, anchor recreation, and the same 30-second idle path; verify the root anchor and expected chunk ledger, then rebuild missing/corrupt chunks.
9. Instrument exact-array audit, entity audit, targeted repair, chunk rebuild, and full rebuild as stable signpost intervals using the same clock and fixture labels created in Task 10. These intervals are the source for Task 14 exports.
10. Add a DEBUG-only `ReconciliationFaultPanel`, reachable from `RenderBenchmarkView`, with typed buttons/APIs for `(a)` mirror plus rendered-chunk corruption, `(b)` injected constant `BoardDigestV1`, and `(c)` deletion of a named RealityKit chunk. Every injection generates and displays a run ID and fault ID and emits them in signposts; Release builds must not expose the route. Define expected evidence: (a) O(1) mismatch→targeted repair, (b) 30-second exact audit→repair despite digest equality, and (c) ledger audit→missing-chunk rebuild.
11. Run the same focused suites GREEN, plus device checks for all three fault IDs; capture before/after snapshot digest, expected repair interval, repaired coordinate/chunk, elapsed time, screenshot, and raw trace reference.
12. Commit: `feat: reconcile AR rendering from authoritative snapshots`.

### Task 14: Performance, accessibility, and release acceptance

**Files:**

- Create: `docs/verification/ar-device-acceptance.md`
- Create: `docs/verification/artifacts/acceptance-v1/metrics.csv`
- Create: `docs/verification/artifacts/acceptance-v1/trace-manifest.txt`
- Modify as required by failed accessibility acceptance: `Three-dimensional Go/Features/Setup/GameSetupView.swift`
- Modify as required by failed accessibility acceptance: `Three-dimensional Go/Features/Tutorial/SurfaceToVolumeTutorial.swift`
- Modify as required by failed accessibility acceptance: `Three-dimensional Go/AR/ARPlacementView.swift`
- Modify as required by failed accessibility acceptance: `Three-dimensional Go/AR/CenterReticleView.swift`
- Modify as required by failed accessibility acceptance: `Three-dimensional Go/Features/Game/GameHUD.swift`
- Modify as required by failed accessibility acceptance: `Three-dimensional Go/Features/Game/GameView.swift`
- Modify as required by failed accessibility acceptance: `Three-dimensional Go/Features/Game/DeadGroupReviewView.swift`
- Modify as required by failed accessibility acceptance: the corresponding tests from Tasks 8, 9, 11, and 12
- Modify: `README.md`

**Steps:**

1. Run the complete unit-test suite and a clean app build; record commands, destination, timestamp, and failure count.
2. Use the fixed baseline: iPhone 12 on the latest available iOS 26.x, Release configuration, Low Power Mode off, brightness 50%, starting thermal state nominal, and no screen recording during measurement. If unavailable, mark this task blocked instead of substituting a faster device for completion.
3. Reuse `empty-v1`, `checker-half-v1`, `split-dense-v1`, the committed 300-entry move workload, and the committed 300-entry `reticle-v1` workload exactly. Warm each fixture for 30 seconds, sample for 120 seconds, and repeat three runs. Drive all samples through `PerformanceHarness`; no freehand camera movement is a benchmark sample.
4. Each move sample starts by resetting outside the measured interval to the exact fixture/preDigest, then sends its committed workload Place through `RuleEngine`; only the accepted transition publication begins `move.render`, and renderer-delta commit ends it. Record postDigest and require the workload golden value. Reset/loading time is excluded. Never chain measured moves or inject renderer-only deltas.
5. For each fixture/run, independently execute that fixture's 100 move samples and its 100 `reticle-v1` samples after resetting the fixture/board transform outside each measured interval; verify the fixture preDigest before every sample. Every run/fixture independently requires p5 FPS ≥30 from instant `frame.present` timestamps, reticle p95 <100 ms, and move-to-render p95 <16.7 ms; never pool samples. Also require no serious/critical thermal state during a separate 10-minute dense run.
6. `metrics.csv` has fixed UTF-8 header: `fixture_id,run_id,metric,unit,valid_count,invalid_count,p50,p95,p5,threshold,passed,trace_sha256`. Durations export in milliseconds and FPS in frames/second. Sort valid samples ascending; nearest-rank percentile uses element `ceil(p*n)` with one-based indexing. A duration sample is valid only when one begin/end pair shares its canonical interval name, correlation ID, fixture/run/sample labels, and expected digests; missing, duplicate, overlapping, mismatched, or rejected-action pairs increment `invalid_count`. An FPS sample is instead one adjacent pair of monotonically increasing instant `frame.present` timestamps with matching fixture/run labels and consecutive frame sequence; missing, duplicate, non-monotonic, cross-run, or non-consecutive events increment `invalid_count`. Invalid samples never enter percentiles, and any invalid move or reticle sample blocks completion.
7. Before profiling, set `THREED_GO_TRACE_ROOT` to a durable, non-temporary artifact directory and `THREED_GO_TRACE_ARCHIVE_URI` to an approved durable location accessible to reviewers. Capture every run with the Task 10 project-owned template and canonical `xcrun xctrace record` command, then run the committed exporter against each `.trace`; hand-edited CSV is invalid. Save raw `.trace` files under the root and upload/archive them without repository credentials. `trace-manifest.txt` records template SHA-256, exporter SHA-256, workload SHA-256 values, content-addressed URI, absolute local path, filename, fixture/run, timestamp, device/OS/build, byte size, and trace SHA-256. A second machine must download a trace by URI, verify its hash, rerun the exporter, and byte-compare `metrics.csv`; missing/inaccessible traces or mismatch blocks completion.
8. Verify horizontal-plane placement, walk-around, pinch zoom, overlapping-point selection, tracking interruption, foreground recovery, Pass/review/Resume, and final scoring on device.
9. Audit VoiceOver labels/values/focus/privacy, Dynamic Type through accessibility sizes, contrast/non-color cues, Reduce Motion, and camera-permission denial across the views named in this task.
10. If an accessibility check fails, first record the failure, then add a focused regression to the corresponding Task 8/9/11/12 test file, confirm RED, make the smallest change to the explicitly listed UI file, rerun the focused test GREEN, and repeat the device inspection. This repair loop is part of Task 14 scope; unresolved failures block completion.
11. Record exact evidence. Any required criterion or threshold not met blocks “implementation complete”; report partial completion. Never treat simulator/build evidence as AR/device acceptance.
12. Run a clean Release build and tests. Stage only Task 14 paths, run both diff checks, re-run affected checks, and inspect status.
13. Commit evidence in either outcome: `docs: record incomplete AR acceptance` when blocked/failed, or `docs: record AR device and performance acceptance` only when all criteria pass. A failure-evidence commit never marks implementation complete.

## Final verification commands

Discover an available simulator once and store its explicit UDID in a task-specific variable:

```bash
xcrun simctl list devices available
export THREED_GO_SIMULATOR_UDID="<SIMULATOR_UDID>"
xcodebuild -project "Three-dimensional Go.xcodeproj" \
  -scheme "Three-dimensional Go" \
  -destination "platform=iOS Simulator,id=$THREED_GO_SIMULATOR_UDID" \
  test
```

Focused-test example used during RED/GREEN cycles:

```bash
xcodebuild -project "Three-dimensional Go.xcodeproj" \
  -scheme "Three-dimensional Go" \
  -destination "platform=iOS Simulator,id=$THREED_GO_SIMULATOR_UDID" \
  -only-testing:"Three-dimensional GoTests/BoardTests" \
  test
```

Build for a connected device or generic device without claiming runtime validation:

```bash
xcodebuild -project "Three-dimensional Go.xcodeproj" \
  -scheme "Three-dimensional Go" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  build
```

Documentation and repository checks:

```bash
git diff --check
git diff --cached --check
git status --short
```

The implementation is complete only when core tests and Debug/Release builds are green, every design success criterion and required performance threshold is met, and the separate AR-device acceptance document contains current evidence for placement, selection, recovery, performance, and accessibility. Evidence of a failed threshold documents partial progress; it does not satisfy completion.
