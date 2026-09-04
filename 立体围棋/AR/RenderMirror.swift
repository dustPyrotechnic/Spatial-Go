import Foundation

/// 一次巡检的访问计数，用于以可测量的方式证明复杂度。
nonisolated struct ReconciliationCounters: Hashable, Sendable {
    /// 只比较 revision、棋盘摘要和固定条数元数据的快速检查次数。
    var digestComparisons: Int = 0
    /// 紧凑数组精确核对访问过的交叉点数。
    var visitedCells: Int = 0
    /// 触发完整重建的次数。
    var rebuilds: Int = 0

    init() {}
}

/// 巡检结论。
nonisolated enum ReconciliationDecision: Equatable {
    /// 棋盘与全部公开元数据都一致，无需触碰实体树。
    case noChange
    /// 按坐标增量修复；调用方应通过 ``RenderMirror/apply(_:from:)`` 落地，
    /// 以便棋盘和元数据在同一次操作中回到快照。
    case apply([BoardDelta])
    /// 镜像不可用，必须从快照完整重建。
    case rebuild
}

/// 渲染层持有的紧凑棋盘镜像。
///
/// 它是不可变 ``GameSnapshot`` 的**完整**单向投影：既镜像棋盘，也镜像
/// ``SnapshotMetadata`` 中的全部公开元数据。停着、认输、死棋提交、公开差异和恢复对局
/// 都没有棋盘增量，但都会改变元数据，因此增量应用和完整重建都必须整体采用动作后的快照。
///
/// 镜像永远不携带权威日志或未公开的死棋提案内容，也永远不反写规则状态。
nonisolated struct RenderMirror: Sendable {
    private(set) var board: Board
    private(set) var revision: UInt64
    private(set) var boardDigest: UInt64
    /// 棋盘之外的全部公开元数据。
    private(set) var metadata: SnapshotMetadata
    private let digester: any BoardDigesting

    init(snapshot: GameSnapshot, digester: any BoardDigesting = BoardDigestV1()) {
        self.board = snapshot.board
        self.revision = snapshot.revision
        self.boardDigest = snapshot.boardDigest
        self.metadata = snapshot.metadata
        self.digester = digester
    }

    var phase: GamePhase { metadata.phase }

    /// 指定一方死棋提案的公共可见状态。
    func deadGroupStatus(for color: Stone) -> DeadGroupSubmissionStatus {
        metadata.deadGroupStatus(for: color)
    }

    /// 消费已经算好的增量，并整体采用该动作之后的快照元数据。
    ///
    /// - Parameters:
    ///   - deltas: 需要落到镜像上的坐标变化量；没有棋盘变化的动作传空数组。
    ///   - snapshot: 该动作被接受之后的规则层快照。
    mutating func apply(_ deltas: [BoardDelta], from snapshot: GameSnapshot) {
        for delta in deltas where board.contains(delta.position) {
            board[delta.position] = delta.stone
        }
        revision = snapshot.revision
        metadata = snapshot.metadata
        boardDigest = digester.digest(board)
    }

    /// 从快照完整重建镜像的每一个字段。
    mutating func rebuild(from snapshot: GameSnapshot) {
        board = snapshot.board
        revision = snapshot.revision
        boardDigest = snapshot.boardDigest
        metadata = snapshot.metadata
    }

    /// 与快照巡检。
    ///
    /// 先判断镜像是否可用和尺寸是否匹配，再做快速比较：revision、棋盘摘要，
    /// 以及固定条数的公开元数据。它不遍历棋盘字节，也不遍历实体树，因此可以按
    /// 2–3 秒的周期运行。只有快速比较不通过时，才付出 `O(交叉点数)` 的紧凑数组精确核对。
    ///
    /// 摘要相同不是内容相等的证明；覆盖摘要碰撞仍由低频的紧凑数组精确核对负责。
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
        if revision == snapshot.revision,
            boardDigest == snapshot.boardDigest,
            metadata == snapshot.metadata
        {
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
