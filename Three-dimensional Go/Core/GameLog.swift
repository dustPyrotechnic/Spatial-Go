import Foundation

/// 权威日志的创建头。
///
/// 记录规则版本、日志格式版本和完整创建配置；配置中的初始布子已按锚点顺序规范排序。
nonisolated struct GameLogHeader: Hashable, Sendable {
    /// 当前规则版本。
    static let currentRulesVersion = "3d-go/1"
    /// 当前日志格式版本。
    static let currentLogFormatVersion = 1

    let rulesVersion: String
    let logFormatVersion: Int
    let configuration: GameConfiguration

    init(configuration: GameConfiguration) {
        self.rulesVersion = GameLogHeader.currentRulesVersion
        self.logFormatVersion = GameLogHeader.currentLogFormatVersion
        self.configuration = configuration
    }

    /// 创建时的初始布子，按锚点顺序排列。
    var initialStones: [PlacedStone] { configuration.initialStones }
}

/// 权威日志中的一条已接受动作记录。
nonisolated struct GameLogEntry: Hashable, Sendable {
    /// 接受该动作后的状态修订号。
    let revision: UInt64
    /// 完整动作载荷。
    let action: GameAction
}

/// 私有权威日志。
///
/// 只记录已接受的动作；被拒绝的动作不写入任何内容。日志必须能确定性重放到相同状态。
nonisolated struct GameLog: Hashable, Sendable {
    let header: GameLogHeader
    private(set) var entries: [GameLogEntry] = []

    init(header: GameLogHeader) {
        self.header = header
    }

    /// 追加一条已接受动作记录。
    mutating func append(revision: UInt64, action: GameAction) {
        entries.append(GameLogEntry(revision: revision, action: action))
    }
}
