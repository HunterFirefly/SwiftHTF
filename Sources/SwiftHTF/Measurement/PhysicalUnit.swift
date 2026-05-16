import Foundation

/// 物理量纲：把"单位"按物理含义分组，以便框架做维度校验。
///
/// 设计取舍：
/// - 与 OpenHTF `pint` 库对齐"按 dimensionality 分组"的思路，但只校验"维度匹配"，
///   不做单位间数学运算（电压 ÷ 电流 → 电阻）—— 测试场景几乎用不到
/// - 覆盖电子测试 + 物理量常用领域；不在内的用 `.custom(_:)` 扩展
/// - `.custom("x")` 仅在 name 相同时算同维度（用作字符串标签），不与内置维度互通
public enum PhysicalDimension: Hashable, Sendable, Codable {
    /// 无量纲（比例 / 占空比 / 计数）
    case dimensionless

    // 电学
    case voltage
    case current
    case resistance
    case capacitance
    case inductance
    case charge
    case conductance
    case magneticFlux
    case power
    case energy

    // 时频
    case frequency
    case time

    /// 温度
    case temperature

    // 力学 / 通用
    case length
    case mass
    case pressure
    case angle

    // 数据 / IO
    case dataSize
    case dataRate

    /// 用户自定义维度（按 name 相等判定）。框架不知其物理含义，仅做字符串维度标签。
    case custom(String)
}

// MARK: - Unit

/// 单位：name + 所属物理维度。
///
/// 内置常量覆盖电子测试常用（V / mV / µV / kV / A / mA / Hz / kHz / MHz / °C / ...）；
/// 自定义维度通过 `Unit(name:dimension:)` 构造，加入 `UnitRegistry.default` 后 harvest
/// 才能反查到。
public struct Unit: Sendable, Hashable, Codable {
    public let name: String
    public let dimension: PhysicalDimension

    public init(name: String, dimension: PhysicalDimension) {
        self.name = name
        self.dimension = dimension
    }
}

public extension Unit {
    // MARK: - 电学

    static let volt = Unit(name: "V", dimension: .voltage)
    static let millivolt = Unit(name: "mV", dimension: .voltage)
    static let microvolt = Unit(name: "µV", dimension: .voltage)
    static let kilovolt = Unit(name: "kV", dimension: .voltage)

    static let ampere = Unit(name: "A", dimension: .current)
    static let milliampere = Unit(name: "mA", dimension: .current)
    static let microampere = Unit(name: "µA", dimension: .current)
    static let nanoampere = Unit(name: "nA", dimension: .current)

    static let ohm = Unit(name: "Ω", dimension: .resistance)
    static let kilohm = Unit(name: "kΩ", dimension: .resistance)
    static let megohm = Unit(name: "MΩ", dimension: .resistance)
    static let milliohm = Unit(name: "mΩ", dimension: .resistance)

    static let farad = Unit(name: "F", dimension: .capacitance)
    static let microfarad = Unit(name: "µF", dimension: .capacitance)
    static let nanofarad = Unit(name: "nF", dimension: .capacitance)
    static let picofarad = Unit(name: "pF", dimension: .capacitance)

    static let henry = Unit(name: "H", dimension: .inductance)
    static let millihenry = Unit(name: "mH", dimension: .inductance)
    static let microhenry = Unit(name: "µH", dimension: .inductance)

    static let coulomb = Unit(name: "C", dimension: .charge)
    static let milliampereHour = Unit(name: "mAh", dimension: .charge)

    static let siemens = Unit(name: "S", dimension: .conductance)
    static let weber = Unit(name: "Wb", dimension: .magneticFlux)

    static let watt = Unit(name: "W", dimension: .power)
    static let milliwatt = Unit(name: "mW", dimension: .power)
    static let kilowatt = Unit(name: "kW", dimension: .power)
    static let dBm = Unit(name: "dBm", dimension: .power)

    static let joule = Unit(name: "J", dimension: .energy)
    static let kilowattHour = Unit(name: "kWh", dimension: .energy)
    static let wattHour = Unit(name: "Wh", dimension: .energy)

    // MARK: - 时频

    static let hertz = Unit(name: "Hz", dimension: .frequency)
    static let kilohertz = Unit(name: "kHz", dimension: .frequency)
    static let megahertz = Unit(name: "MHz", dimension: .frequency)
    static let gigahertz = Unit(name: "GHz", dimension: .frequency)

    static let second = Unit(name: "s", dimension: .time)
    static let millisecond = Unit(name: "ms", dimension: .time)
    static let microsecond = Unit(name: "µs", dimension: .time)
    static let nanosecond = Unit(name: "ns", dimension: .time)
    static let minute = Unit(name: "min", dimension: .time)
    static let hour = Unit(name: "h", dimension: .time)

    // MARK: - 温度

    static let celsius = Unit(name: "°C", dimension: .temperature)
    static let fahrenheit = Unit(name: "°F", dimension: .temperature)
    static let kelvin = Unit(name: "K", dimension: .temperature)

    // MARK: - 力学 / 通用

    static let meter = Unit(name: "m", dimension: .length)
    static let millimeter = Unit(name: "mm", dimension: .length)
    static let centimeter = Unit(name: "cm", dimension: .length)
    static let kilometer = Unit(name: "km", dimension: .length)

    static let kilogram = Unit(name: "kg", dimension: .mass)
    static let gram = Unit(name: "g", dimension: .mass)

    static let pascal = Unit(name: "Pa", dimension: .pressure)
    static let kilopascal = Unit(name: "kPa", dimension: .pressure)
    static let bar = Unit(name: "bar", dimension: .pressure)

    static let degree = Unit(name: "°", dimension: .angle)
    static let radian = Unit(name: "rad", dimension: .angle)

    // MARK: - 数据 / IO

    static let byte = Unit(name: "B", dimension: .dataSize)
    static let kilobyte = Unit(name: "KB", dimension: .dataSize)
    static let megabyte = Unit(name: "MB", dimension: .dataSize)
    static let gigabyte = Unit(name: "GB", dimension: .dataSize)

    static let bitsPerSecond = Unit(name: "bps", dimension: .dataRate)
    static let kilobitsPerSecond = Unit(name: "kbps", dimension: .dataRate)
    static let megabitsPerSecond = Unit(name: "Mbps", dimension: .dataRate)

    // MARK: - 无量纲

    static let percent = Unit(name: "%", dimension: .dimensionless)
    static let count = Unit(name: "count", dimension: .dimensionless)
    static let ratio = Unit(name: "ratio", dimension: .dimensionless)
}

// MARK: - UnitRegistry

/// 按 name 反查 Unit；harvest 时把 measurement 上的 unit 字符串解析回 Unit 做维度校验。
///
/// 内置常量自动注册；用户的自定义 unit 调 `register(_:)` 加入后才能被反查。
public final class UnitRegistry: @unchecked Sendable {
    /// 默认全局实例：测试 / SwiftUI 应用共用一份。
    public static let `default` = UnitRegistry(builtins: true)

    private let lock = NSLock()
    private var nameToUnit: [String: Unit] = [:]

    /// - Parameter builtins: 是否预注册 Unit 类型上的所有内置常量
    public init(builtins: Bool = true) {
        if builtins {
            registerBuiltins()
        }
    }

    /// 注册自定义 Unit。重复 name 会**覆盖**，便于用户在测试入口处替换。
    public func register(_ unit: Unit) {
        lock.lock()
        defer { lock.unlock() }
        nameToUnit[unit.name] = unit
    }

    /// 按字面 name 查 Unit（含大小写敏感）；找不到返回 nil。
    public func unit(named name: String) -> Unit? {
        lock.lock()
        defer { lock.unlock() }
        return nameToUnit[name]
    }

    private func registerBuiltins() {
        for unit in builtinUnits {
            nameToUnit[unit.name] = unit
        }
    }

    /// 内置 Unit 全集；维护新增内置时同步追加。
    private var builtinUnits: [Unit] {
        [
            // 电学
            .volt, .millivolt, .microvolt, .kilovolt,
            .ampere, .milliampere, .microampere, .nanoampere,
            .ohm, .kilohm, .megohm, .milliohm,
            .farad, .microfarad, .nanofarad, .picofarad,
            .henry, .millihenry, .microhenry,
            .coulomb, .milliampereHour,
            .siemens, .weber,
            .watt, .milliwatt, .kilowatt, .dBm,
            .joule, .kilowattHour, .wattHour,
            // 时频
            .hertz, .kilohertz, .megahertz, .gigahertz,
            .second, .millisecond, .microsecond, .nanosecond, .minute, .hour,
            // 温度
            .celsius, .fahrenheit, .kelvin,
            // 力学
            .meter, .millimeter, .centimeter, .kilometer,
            .kilogram, .gram,
            .pascal, .kilopascal, .bar,
            .degree, .radian,
            // 数据 / IO
            .byte, .kilobyte, .megabyte, .gigabyte,
            .bitsPerSecond, .kilobitsPerSecond, .megabitsPerSecond,
            // 无量纲
            .percent, .count, .ratio,
        ]
    }
}
