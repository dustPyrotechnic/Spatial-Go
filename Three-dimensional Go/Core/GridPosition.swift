import Foundation

/// 三维棋盘上的一个零基整数交叉点坐标。
///
/// 规则层只使用整数坐标；空间坐标转换属于 AR 展示层。
nonisolated struct GridPosition: Hashable, Codable, Sendable {
    let x: Int
    let y: Int
    let z: Int

    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// `nonisolated` 是必需的：默认 actor 隔离为 MainActor 时，未标注的见证方法会被视为
/// MainActor 隔离，纯 Core 的同步代码就无法调用它。
nonisolated extension GridPosition: Comparable {
    /// 锚点顺序：先比较 x，再比较 y，最后比较 z。
    ///
    /// 这是棋块 `anchor` 使用的字典序，和棋盘序列化使用的 z/y/x 顺序是两套独立顺序。
    static func < (lhs: GridPosition, rhs: GridPosition) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.z < rhs.z
    }
}

nonisolated extension GridPosition: CustomStringConvertible {
    var description: String { "(\(x), \(y), \(z))" }
}
