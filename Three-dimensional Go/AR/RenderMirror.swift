import Foundation

/// 一次巡检的访问计数，用于以可测量的方式证明复杂度。
nonisolated struct ReconciliationCounters: Hashable, Sendable {
    /// 只比较 revision/摘要的 `O(1)` 检查次数。
    var digestComparisons: Int = 0
    /// 紧凑数组精确核对访问过的交叉点数。
    var visitedCells: Int = 0
    /// 触发完整重建的次数。
    var rebuilds: Int = 0

    init() {}
}

/// 巡检结论。
nonisolated enum ReconciliationDecision: Equatable {
    /// 摘要与修订号一致，无需触碰实体树。
    case noChange
    /// 按坐标增量修复。
    case apply([BoardDelta])
    /// 镜像不可用，必须从快照完整重建。
    case rebuild
}

/// 渲染层持有的紧凑棋盘镜像。
///
/// 它是不可变 ``GameSnapshot`` 的单向投影：正常路径消费动作增量，
/// 周期性巡检只比较 revision 和棋盘摘要，只有摘要不一致时才做数组精确核对。
/// 镜像永远不携带权威日志或未公开的死棋提案内容，也永远不反写规则状态。
nonisolated struct RenderMirror: Sendable {
    private(set) var board: Board
    private(set) var revision: UInt64
    private(set) var boardDigest: UInt64
    private(set) var phase: GamePhase
    private let submissionStatus: [Stone: DeadGroupSubmissionStatus]
    private let digester: any BoardDigesting

    init(snapshot: GameSnapshot, digester: any BoardDigesting = BoardDigestV1()) {
        self.board = snapshot.board
        self.revision = snapshot.revision
        self.boardDigest = snapshot.boardDigest
        self.phase = snapshot.phase
        self.submissionStatus = [
            .black: snapshot.deadGroupStatus(for: .black),
            .white: snapshot.deadGroupStatus(for: .white),
        ]
        self.digester = digester
    }

    /// 指定一方死棋提案的公共可见状态。
    func deadGroupStatus(for color: Stone) -> DeadGroupSubmissionStatus {
        submissionStatus[color] ?? .notSubmitted
    }

    /// 消费已经算好的增量。
    ///
    /// - Parameters:
    ///   - deltas: 需要落到镜像上的坐标变化量。
    ///   - revision: 增量对应的状态修订号；`nil` 表示只改镜像、不推进修订号。
    mutating func apply(_ deltas: [BoardDelta], revision: UInt64? = nil) {
        for delta in deltas where board.contains(delta.position) {
            board[delta.position] = delta.stone
        }
        if let revision {
            self.revision = revision
        }
        boardDigest = digester.digest(board)
    }

    /// 从快照完整重建镜像。
    mutating func rebuild(from snapshot: GameSnapshot) {
        board = snapshot.board
        revision = snapshot.revision
        boardDigest = snapshot.boardDigest
        phase = snapshot.phase
    }

    /// 与快照巡检。
    ///
    /// 先判断镜像是否可用和尺寸是否匹配，再做 `O(1)` 的 revision/摘要比较；
    /// 只有比较不通过时才付出 `O(交叉点数)` 的紧凑数组精确核对。
    ///
    /// - Parameters:
    ///   - snapshot: 规则层的当前快照。
    ///   - mirrorIsIntact: 实体账本审计结论；为 `false` 时直接要求完整重建。
    ///   - counters: 访问计数器，用于验证复杂度。
    /// - Returns: 巡检结论。
    func reconcile(
        with snapshot: GameSnapshot,
        mirrorIsIntact: Bool = true,
        counters: inout ReconciliationCounters
    ) -> ReconciliationDecision {
        guard mirrorIsIntact else {
            counters.rebuilds += 1
            return .rebuild
        }
        guard board.width == snapshot.board.width,
            board.height == snapshot.board.height,
            board.depth == snapshot.board.depth
        else {
            counters.rebuilds += 1
            return .rebuild
        }

        counters.digestComparisons += 1
        if revision == snapshot.revision && boardDigest == snapshot.boardDigest {
            return .noChange
        }

        var deltas = [BoardDelta]()
        for index in 0..<snapshot.board.pointCount {
            counters.visitedCells += 1
            guard board.cells[index] != snapshot.board.cells[index] else { continue }
            deltas.append(
                BoardDelta(
                    position: snapshot.board.position(atLinearIndex: index),
                    stone: snapshot.board.cells[index]
                )
            )
        }
        return .apply(deltas)
    }
}
