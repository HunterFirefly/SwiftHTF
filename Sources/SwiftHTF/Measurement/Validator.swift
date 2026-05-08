import Foundation

/// 验证器协议
public protocol Validator: Sendable {
    /// 验证值
    /// - Parameter value: 要验证的值
    /// - Returns: 验证结果
    func validate(_ value: String) -> ValidationResult
}

/// 验证结果
public enum ValidationResult: Sendable {
    case pass
    case fail(String)
}

/// 范围验证器（支持十进制与 0x 十六进制）
public struct RangeValidator: Validator {
    let lower: Double?
    let upper: Double?
    let unit: String?

    public init(lower: Double? = nil, upper: Double? = nil, unit: String? = nil) {
        self.lower = lower
        self.upper = upper
        self.unit = unit
    }

    public func validate(_ value: String) -> ValidationResult {
        guard let numValue = Self.parseNumber(value) else {
            return .fail("无法解析为数字: \(value)")
        }

        if let lower, numValue < lower {
            return .fail("值 \(numValue) 小于下限 \(lower)")
        }

        if let upper, numValue > upper {
            return .fail("值 \(numValue) 大于上限 \(upper)")
        }

        return .pass
    }

    /// 解析数字字面量，支持十进制（含小数）与 0x 十六进制
    public static func parseNumber(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("0x"),
           let i = UInt64(trimmed.dropFirst(2), radix: 16) {
            return Double(i)
        }
        return Double(trimmed)
    }
}

/// 相等验证器
public struct EqualsValidator: Validator {
    let expected: String
    
    public init(_ expected: String) {
        self.expected = expected
    }
    
    public func validate(_ value: String) -> ValidationResult {
        if value == expected {
            return .pass
        }
        return .fail("值 '\(value)' 不等于期望值 '\(expected)'")
    }
}

/// 正则验证器
public struct RegexValidator: Validator {
    let pattern: String
    
    public init(_ pattern: String) {
        self.pattern = pattern
    }
    
    public func validate(_ value: String) -> ValidationResult {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return .fail("无效的正则表达式: \(pattern)")
        }
        
        let range = NSRange(value.startIndex..., in: value)
        if regex.firstMatch(in: value, range: range) != nil {
            return .pass
        }
        return .fail("值 '\(value)' 不匹配正则 '\(pattern)'")
    }
}

/// 非空验证器
public struct NotEmptyValidator: Validator {
    public init() {}
    
    public func validate(_ value: String) -> ValidationResult {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .fail("值不能为空")
        }
        return .pass
    }
}
