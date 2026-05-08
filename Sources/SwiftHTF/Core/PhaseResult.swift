import Foundation

/// Phase 执行结果
public enum PhaseResult: Sendable {
    /// 继续执行下一阶段
    case `continue`
    /// 标记失败但继续执行
    case failAndContinue
    /// 重复当前阶段
    case retry
    /// 跳过当前阶段
    case skip
    /// 立即终止测试
    case stop
}
