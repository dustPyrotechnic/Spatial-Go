import Testing

@testable import Three_dimensional_Go

/// 断言动作被规则核心拒绝，且拒绝前后的完整权威状态逐字段相等。
///
/// `GameState` 是 `Equatable` 的，因此这一次比较同时覆盖棋盘、轮次、阶段、提子数、
/// 修订号、超级劫历史和权威日志。
///
/// - Parameters:
///   - engine: 待测规则引擎。
///   - action: 预期被拒绝的动作。
///   - violation: 预期的稳定错误值。
///   - sourceLocation: 调用点位置，用于把失败定位到具体测试而不是本辅助函数。
func expectAtomicRejection(
    _ engine: inout RuleEngine,
    _ action: GameAction,
    _ violation: RuleViolation,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let before = engine.state
    #expect(throws: violation, sourceLocation: sourceLocation) {
        try engine.apply(action)
    }
    #expect(engine.state == before, sourceLocation: sourceLocation)
}
