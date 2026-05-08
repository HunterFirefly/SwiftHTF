import Foundation

/// JSON 兼容的递归 Codable 值
///
/// 类型化测量值的存储形式。Phase 代码通过 `TestContext.measure(...)` 写入泛型值，
/// 框架在内部归一化为 `AnyCodableValue` — 既保留结构信息（区分 int/double/string/...）
/// 又能直接 JSON 编解码。
public indirect enum AnyCodableValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    // MARK: - Decoding

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int64.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyCodableValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: AnyCodableValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodableValue: 不支持的 JSON 值"
            )
        }
    }

    // MARK: - Encoding

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    // MARK: - 类型化访问器

    public var asBool: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    public var asInt: Int? {
        switch self {
        case .int(let v): return Int(exactly: v)
        case .double(let v) where v.rounded() == v: return Int(exactly: v)
        default: return nil
        }
    }

    public var asDouble: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    public var asString: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// 把任意值显示为字符串（用于 CSV 输出、日志）
    public var displayString: String {
        switch self {
        case .null: return ""
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .string(let v): return v
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(self), let s = String(data: data, encoding: .utf8) {
                return s
            }
            return ""
        }
    }

    // MARK: - 工厂

    /// 从任意 `Encodable` 值构造（通过 JSON 中转），失败时返回 `.null`
    public static func from<T: Encodable>(_ value: T) -> AnyCodableValue {
        // 快速路径
        switch value {
        case let v as Bool: return .bool(v)
        case let v as Int: return .int(Int64(v))
        case let v as Int64: return .int(v)
        case let v as Double: return .double(v)
        case let v as Float: return .double(Double(v))
        case let v as String: return .string(v)
        default: break
        }
        // 通用路径：编码到 JSON 再解码
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return .null }
        let decoder = JSONDecoder()
        return (try? decoder.decode(AnyCodableValue.self, from: data)) ?? .null
    }
}
