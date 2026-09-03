import Foundation

/// 情境超级劫使用的完整状态键。
///
/// 由棋盘尺寸、按规范 z/y/x 顺序展开的完整棋盘和下一行棋方组成。
/// 摘要只是查找加速手段，判定重复必须比较完整键值。
nonisolated struct StateKey: Hashable, Sendable {
    /// 空点在规范字节序列中的取值。
    static let emptyByte: UInt8 = 0

    let width: UInt8
    let height: UInt8
    let depth: UInt8
    /// 按 z、再 y、再 x 展开的棋盘字节：空 0、黑 1、白 2。
    let boardBytes: [UInt8]
    let nextPlayer: Stone

    /// 由棋盘和下一行棋方构造状态键。
    init(board: Board, nextPlayer: Stone) {
        self.width = UInt8(board.width)
        self.height = UInt8(board.height)
        self.depth = UInt8(board.depth)
        self.boardBytes = board.cells.map { $0?.rawValue ?? StateKey.emptyByte }
        self.nextPlayer = nextPlayer
    }

    /// 状态键的规范字节序列：三个尺寸、棋盘字节、下一行棋方。
    var canonicalBytes: [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(boardBytes.count + 4)
        bytes.append(contentsOf: [width, height, depth])
        bytes.append(contentsOf: boardBytes)
        bytes.append(nextPlayer.rawValue)
        return bytes
    }
}

/// 状态键摘要算法。
///
/// 摘要只用于加速超级劫查找；命中后仍必须比较完整 ``StateKey``。
nonisolated protocol StateKeyDigesting: Sendable {
    /// 计算状态键的 64 位摘要。
    func digest(_ key: StateKey) -> UInt64
}

/// `3d-go/1` 的默认摘要：对域前缀 `3dgo-state-v1\0` 与状态键规范字节做 FNV-1a 64。
nonisolated struct StateKeyDigestV1: StateKeyDigesting {
    /// ASCII 域前缀，含结尾的 0 字节。
    static let domainPrefix: [UInt8] = Array("3dgo-state-v1".utf8) + [0]

    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    init() {}

    func digest(_ key: StateKey) -> UInt64 {
        var hash = StateKeyDigestV1.offsetBasis
        for byte in StateKeyDigestV1.domainPrefix {
            hash = (hash ^ UInt64(byte)) &* StateKeyDigestV1.prime
        }
        for byte in key.canonicalBytes {
            hash = (hash ^ UInt64(byte)) &* StateKeyDigestV1.prime
        }
        return hash
    }
}

/// 情境超级劫历史。
///
/// 按摘要分桶保存完整状态键；摘要相同只表示需要比较，从不单独构成拒绝理由。
nonisolated struct SuperkoHistory: Hashable, Sendable {
    private var buckets: [UInt64: [StateKey]] = [:]

    init() {}

    /// 历史中保存的完整状态键数量。
    var count: Int { buckets.values.reduce(0) { $0 + $1.count } }

    /// 判断状态键是否已经出现过。摘要命中后仍比较完整键值。
    func contains(_ key: StateKey, digest: UInt64) -> Bool {
        buckets[digest]?.contains(key) ?? false
    }

    /// 写入一个状态键；重复写入同一键不会产生第二份记录。
    mutating func insert(_ key: StateKey, digest: UInt64) {
        guard !contains(key, digest: digest) else { return }
        buckets[digest, default: []].append(key)
    }
}
