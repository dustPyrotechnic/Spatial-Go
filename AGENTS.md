# 立体围棋 agent instructions

## Start here

- Rules, scoring, AR selection, rendering, or synchronization changes: read `docs/plans/2026-09-03-立体围棋-design.md` first.
- Planned implementation work: read the matching task in `docs/plans/2026-09-03-立体围棋-implementation.md` and execute only that task's scope.
- Preserve user-owned `立体围棋.xcodeproj/xcuserdata/`; never stage or delete it.

## Architectural invariants

- `Go3DCore` is the only authority for board state, turn, legality, scoring, log, revision, and digest.
- Core code imports Swift/Foundation only. ARKit, RealityKit, SwiftUI, player controllers, and persistence adapters depend on the core; the core never depends on them.
- RealityKit entities are projections of immutable `GameSnapshot` values. Rendering and reconciliation never write game state backward.
- Every accepted rules action is atomic and logged with its complete payload. Every rejected action leaves all state, superko history, counters, proposals, revisions, and logs unchanged.
- Use the audited `3d-go/1` rules. A semantic rule change requires a new rule version, updated fixtures/docs, and an independent blank review before implementation.
- `ComputerPlayer` remains an empty seam until an AI task is explicitly approved. Manual black/white control still obeys `nextPlayer`.

## Implementation discipline

- Follow test-driven development for rule, selection, synchronization, and scoring behavior: focused RED, minimal GREEN, then refactor.
- Keep coordinates zero-based. Canonical board serialization iterates z, then y, then x; GroupID anchors are the actual group coordinate with lexicographic minimum x, then y, then z. Keep separate fixtures for both orders.
- Use six-direction orthogonal adjacency only. Compute all captured enemy groups before checking the placed stone's liberties.
- Compare full `StateKey` values after digest hits; a hash match alone never rejects a move.
- Prefer contiguous board/SIMD buffers and mesh batching. Full-volume display does not justify one Entity per grid segment.
- Main-thread RealityKit mutations consume already-computed deltas. Keep rule traversal, scoring, digesting, and selection math independently testable.
- Add stable typed errors instead of parsing display strings.

## Verification

- Run focused tests after each RED/GREEN cycle, then the complete affected suite.
- Stage explicit task paths, then run both `git diff --check` and `git diff --cached --check` before every commit; inspect `git status --short` for unrelated and untracked files.
- A simulator build proves compilation only. Report horizontal-plane detection, world-anchor stability, physical walk-around selection, camera permission, performance, thermals, and tracking recovery only with current ARKit-device evidence.
- Record `19×19×19` empty, half-filled, and dense-board results separately. Do not infer high-density performance from a small board.
- Build/test success does not prove visual layout, VoiceOver, Dynamic Type, contrast, Reduce Motion, or touch accuracy; verify each through the appropriate UI/device workflow.

## Commit boundaries

- Keep commits aligned with one implementation-plan task.
- Stage explicit paths. Leave unrelated workspace changes untouched.
- Update README capability status only after fresh verification demonstrates that capability.
