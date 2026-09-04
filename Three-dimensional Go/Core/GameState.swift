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
    /// 连续停着数；合法落子后归零。
    private(set) var consecutivePasses: UInt8
    /// 已经进入过的计分审核轮数。恢复对局不递增。
    private(set) var reviewIndex: UInt32
    /// 当前活动审核轮次；离开审核阶段后立即失效。
    private(set) var currentReviewID: ReviewID?
    /// 终局结果；未结束时为 `nil`。
    private(set) var result: GameResult?
    /// 情境超级劫历史，创建成功的初始状态键即已写入。
    private(set) var superkoSeen: SuperkoHistory
    /// 私有权威日志，只记录已接受的动作。
    private(set) var log: GameLog

    /// 由配置创建初始状态。
    ///
    /// - Parameters:
    ///   - configuration: 已校验的创建配置。
    ///   - digester: 计算超级劫摘要使用的实现。
    init(configuration: GameConfiguration, digester: any StateKeyDigesting = StateKeyDigestV1()) {
        self.configuration = configuration
        self.board = configuration.board
        self.nextPlayer = configuration.nextPlayer
        self.phase = .playing
        self.capturedByBlack = 0
        self.capturedByWhite = 0
        self.revision = 0
        self.consecutivePasses = 0
        self.reviewIndex = 0
        self.currentReviewID = nil
        self.result = nil
        self.superkoSeen = SuperkoHistory()
        self.log = GameLog(header: GameLogHeader(configuration: configuration))
        let key = StateKey(board: board, nextPlayer: nextPlayer)
        self.superkoSeen.insert(key, digest: digester.digest(key))
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
        revision: UInt64,
        consecutivePasses: UInt8 = 0,
        reviewIndex: UInt32 = 0,
        currentReviewID: ReviewID? = nil,
        result: GameResult? = nil,
        superkoSeen: SuperkoHistory = SuperkoHistory(),
        log: GameLog? = nil
    ) {
        self.configuration = configuration
        self.board = board
        self.nextPlayer = nextPlayer
        self.phase = phase
        self.capturedByBlack = capturedByBlack
        self.capturedByWhite = capturedByWhite
        self.revision = revision
        self.consecutivePasses = consecutivePasses
        self.reviewIndex = reviewIndex
        self.currentReviewID = currentReviewID
        self.result = result
        self.superkoSeen = superkoSeen
        self.log = log ?? GameLog(header: GameLogHeader(configuration: configuration))
    }

    /// 指定一方累计提走的敌方棋子颗数。
    func capturedStones(by player: Stone) -> UInt64 {
        player == .black ? capturedByBlack : capturedByWhite
    }

    /// 按当前棋盘和创建时的贴目做三维面积计分。
    ///
    /// - Parameter deadStones: 双方约定的死棋坐标，计分前移除；缺省为空。
    /// - Returns: 完整计分明细。
    func areaScore(removingDeadStones deadStones: Set<GridPosition> = []) -> AreaScoreBreakdown {
        TerritoryScorer.score(
            board: board,
            removingDeadStones: deadStones,
            komiHalfPoints: configuration.komiHalfPoints
        )
    }

    /// 原子提交一次已通过全部校验的落子结果。
    ///
    /// - Parameters:
    ///   - board: 已经完成提子的候选棋盘。
    ///   - capturedCount: 本次提走的敌方棋子颗数。
    ///   - actor: 落子方。
    ///   - stateKey: 落子后的完整状态键。
    ///   - digest: 该状态键的摘要。
    ///   - action: 写入权威日志的完整动作载荷。
    /// - Throws: 提子计数或修订号 checked 运算溢出时抛出 ``RuleViolation/arithmeticOverflow``。
    mutating func commitPlacement(
        board: Board,
        capturedCount: Int,
        actor: Stone,
        stateKey: StateKey,
        digest: UInt64,
        action: GameAction
    ) throws {
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
        self.consecutivePasses = 0
        self.superkoSeen.insert(stateKey, digest: digest)
        self.log.append(revision: nextRevision, action: action)
    }

    /// 原子提交一次停着。
    ///
    /// 停着不改变棋盘，切换行棋方，并把完整状态键写入超级劫历史和权威日志。
    /// 第二次连续停着会对 ``reviewIndex`` 做 checked `+1` 并进入计分审核。
    ///
    /// - Parameters:
    ///   - actor: 停着方。
    ///   - stateKey: 停着后的完整状态键。
    ///   - digest: 该状态键的摘要。
    ///   - action: 写入权威日志的完整动作载荷。
    /// - Returns: 本次停着是否使棋局进入计分审核。
    /// - Throws: 修订号、连续停着数或审核轮次 checked 运算溢出时抛出
    ///   ``RuleViolation/arithmeticOverflow``。
    mutating func commitPass(
        actor: Stone,
        stateKey: StateKey,
        digest: UInt64,
        action: GameAction
    ) throws -> Bool {
        let (nextRevision, revisionOverflow) = revision.addingReportingOverflow(1)
        guard !revisionOverflow else { throw RuleViolation.arithmeticOverflow }
        let (passes, passOverflow) = consecutivePasses.addingReportingOverflow(1)
        guard !passOverflow else { throw RuleViolation.arithmeticOverflow }

        var enteredReview = false
        var nextReviewIndex = reviewIndex
        if passes == 2 {
            let (incremented, indexOverflow) = reviewIndex.addingReportingOverflow(1)
            guard !indexOverflow else { throw RuleViolation.arithmeticOverflow }
            nextReviewIndex = incremented
            enteredReview = true
        }

        self.nextPlayer = actor.opponent
        self.revision = nextRevision
        self.consecutivePasses = passes
        if enteredReview {
            self.reviewIndex = nextReviewIndex
            self.currentReviewID = ReviewID(value: nextReviewIndex)
            self.phase = .scoringReview
        }
        self.superkoSeen.insert(stateKey, digest: digest)
        self.log.append(revision: nextRevision, action: action)
        return enteredReview
    }

    /// 原子提交一次认输。
    ///
    /// 棋盘、``nextPlayer``、提子数、超级劫历史和连续停着数都保持不变。
    ///
    /// - Parameters:
    ///   - actor: 认输方。
    ///   - action: 写入权威日志的完整动作载荷。
    /// - Throws: 修订号 checked 运算溢出时抛出 ``RuleViolation/arithmeticOverflow``。
    mutating func commitResign(actor: Stone, action: GameAction) throws {
        let (nextRevision, revisionOverflow) = revision.addingReportingOverflow(1)
        guard !revisionOverflow else { throw RuleViolation.arithmeticOverflow }

        self.revision = nextRevision
        self.phase = .finished
        self.result = .resignation(winner: actor.opponent, loser: actor)
        self.log.append(revision: nextRevision, action: action)
    }

    /// 原子提交一次死棋提案。
    ///
    /// 第二份提交时，比较、公开、移除约定死棋、计分、终局结果与阶段切换属于同一次转换。
    ///
    /// - Parameters:
    ///   - action: 已规范化的完整动作载荷。
    ///   - finalBoard: 双方一致时移除死棋后的棋盘；否则为 `nil`。
    ///   - result: 双方一致时的终局结果；否则为 `nil`。
    /// - Throws: 修订号 checked 运算溢出时抛出 ``RuleViolation/arithmeticOverflow``。
    mutating func commitReviewSubmission(
        action: GameAction,
        finalBoard: Board?,
        result: GameResult?
    ) throws {
        let (nextRevision, revisionOverflow) = revision.addingReportingOverflow(1)
        guard !revisionOverflow else { throw RuleViolation.arithmeticOverflow }

        self.revision = nextRevision
        if let finalBoard, let result {
            self.board = finalBoard
            self.result = result
            self.phase = .finished
        }
        self.log.append(revision: nextRevision, action: action)
    }

    /// 原子提交一次恢复对局。
    ///
    /// 清零连续停着数并回到 `playing`，保留棋盘、提子数和超级劫历史；
    /// ``reviewIndex`` 不递增，``nextPlayer`` 不受请求方影响。
    ///
    /// - Parameter action: 写入权威日志的完整动作载荷。
    /// - Throws: 修订号 checked 运算溢出时抛出 ``RuleViolation/arithmeticOverflow``。
    mutating func commitResume(action: GameAction) throws {
        let (nextRevision, revisionOverflow) = revision.addingReportingOverflow(1)
        guard !revisionOverflow else { throw RuleViolation.arithmeticOverflow }

        self.revision = nextRevision
        self.consecutivePasses = 0
        self.currentReviewID = nil
        self.phase = .playing
        self.log.append(revision: nextRevision, action: action)
    }
}
