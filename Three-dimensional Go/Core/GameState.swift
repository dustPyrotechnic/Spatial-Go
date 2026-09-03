import Foundation

/// 棋局阶段。三者与 AR 放置生命周期、跟踪质量互相正交。
nonisolated enum GamePhase: String, Codable, Sendable, CaseIterable {
    case playing
    case scoringReview
    case finished
}

/// 一局三维围棋的规则状态。
///
/// 这是棋盘、轮次、提子数和修订号的唯一权威表示；展示层只读取它的快照。
nonisolated struct GameState: Hashable, Sendable {
    /// 创建对局时使用的配置。
    let configuration: GameConfiguration
    /// 当前棋盘内容。
    private(set) var board: Board
    /// 下一行棋方。
    private(set) var nextPlayer: Stone
    /// 当前棋局阶段。
    private(set) var phase: GamePhase
    /// 黑方累计提子颗数。
    private(set) var capturedByBlack: UInt64
    /// 白方累计提子颗数。
    private(set) var capturedByWhite: UInt64
    /// 状态修订号，每接受一个动作递增一次。
    private(set) var revision: UInt64

    /// 由配置创建初始状态。
    init(configuration: GameConfiguration) {
        self.configuration = configuration
        self.board = configuration.board
        self.nextPlayer = configuration.nextPlayer
        self.phase = .playing
        self.capturedByBlack = 0
        self.capturedByWhite = 0
        self.revision = 0
    }

    /// 由完整字段创建状态。
    ///
    /// 供日志重放和测试注入使用；它不校验该状态是否可由合法对局历史到达。
    init(
        configuration: GameConfiguration,
        board: Board,
        nextPlayer: Stone,
        phase: GamePhase,
        capturedByBlack: UInt64,
        capturedByWhite: UInt64,
        revision: UInt64
    ) {
        self.configuration = configuration
        self.board = board
        self.nextPlayer = nextPlayer
        self.phase = phase
        self.capturedByBlack = capturedByBlack
        self.capturedByWhite = capturedByWhite
        self.revision = revision
    }

    /// 指定一方累计提走的敌方棋子颗数。
    func capturedStones(by player: Stone) -> UInt64 {
        player == .black ? capturedByBlack : capturedByWhite
    }

    /// 原子提交一次已通过全部校验的落子结果。
    ///
    /// - Parameters:
    ///   - board: 已经完成提子的候选棋盘。
    ///   - capturedCount: 本次提走的敌方棋子颗数。
    ///   - actor: 落子方。
    /// - Throws: 提子计数或修订号 checked 运算溢出时抛出 ``RuleViolation/arithmeticOverflow``。
    mutating func commitPlacement(board: Board, capturedCount: Int, actor: Stone) throws {
        let (captured, capturedOverflow) = capturedStones(by: actor)
            .addingReportingOverflow(UInt64(capturedCount))
        guard !capturedOverflow else { throw RuleViolation.arithmeticOverflow }
        let (nextRevision, revisionOverflow) = revision.addingReportingOverflow(1)
        guard !revisionOverflow else { throw RuleViolation.arithmeticOverflow }

        self.board = board
        switch actor {
        case .black: capturedByBlack = captured
        case .white: capturedByWhite = captured
        }
        self.nextPlayer = actor.opponent
        self.revision = nextRevision
    }
}
