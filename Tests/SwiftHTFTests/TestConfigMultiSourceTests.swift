@testable import SwiftHTF
import XCTest

final class TestConfigMultiSourceTests: XCTestCase {
    // MARK: - YAML 加载

    func testLoadYAMLFromData() throws {
        let yaml = """
        vcc:
          lower: 3.0
          upper: 3.6
        operator: alice
        enabled: true
        retries: 3
        """
        let data = Data(yaml.utf8)
        let cfg = try TestConfig.load(from: data, format: .yaml)
        // 嵌套 object 是 .object，访问要走 value(_:as:) 解码
        struct VCC: Decodable, Equatable {
            let lower: Double
            let upper: Double
        }
        let vcc = cfg.value("vcc", as: VCC.self)
        XCTAssertEqual(vcc, VCC(lower: 3.0, upper: 3.6))
        XCTAssertEqual(cfg.string("operator"), "alice")
        XCTAssertEqual(cfg.bool("enabled"), true)
        XCTAssertEqual(cfg.int("retries"), 3)
    }

    func testLoadYAMLFromURL() throws {
        let yaml = """
        sn: SN-001
        vcc_lower: 3.0
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.yaml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        let cfg = try TestConfig.load(from: url)
        XCTAssertEqual(cfg.string("sn"), "SN-001")
        XCTAssertEqual(cfg.double("vcc_lower"), 3.0)
    }

    func testLoadJSONFromURLStillWorks() throws {
        let json = """
        {"sn": "SN-002", "retries": 5}
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        let cfg = try TestConfig.load(from: url)
        XCTAssertEqual(cfg.string("sn"), "SN-002")
        XCTAssertEqual(cfg.int("retries"), 5)
    }

    func testUnknownExtensionThrows() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        try? "x=1".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try TestConfig.load(from: url)) { err in
            guard case TestConfigError.unknownFileExtension = err else {
                XCTFail("expected unknownFileExtension")
                return
            }
        }
    }

    func testYAMLTopLevelMustBeObject() throws {
        let yaml = "- 1\n- 2\n" // 顶层是 array，不允许
        let data = Data(yaml.utf8)
        XCTAssertThrowsError(try TestConfig.load(from: data, format: .yaml)) { err in
            guard case TestConfigError.yamlTopLevelNotObject = err else {
                XCTFail("expected yamlTopLevelNotObject")
                return
            }
        }
    }

    // MARK: - 环境变量

    func testFromEnvironmentDefaultKeyTransform() {
        let env = [
            "SWIFTHTF_VCC_LOWER": "3.0",
            "SWIFTHTF_VCC_UPPER": "3.6",
            "SWIFTHTF_ENABLED": "true",
            "SWIFTHTF_RETRIES": "3",
            "SWIFTHTF_OPERATOR": "alice",
            "OTHER_VAR": "ignored", // 无 prefix，应忽略
        ]
        let cfg = TestConfig.from(environment: env, prefix: "SWIFTHTF_")
        XCTAssertEqual(cfg.double("vcc.lower"), 3.0)
        XCTAssertEqual(cfg.double("vcc.upper"), 3.6)
        XCTAssertEqual(cfg.bool("enabled"), true)
        XCTAssertEqual(cfg.int("retries"), 3)
        XCTAssertEqual(cfg.string("operator"), "alice")
        XCTAssertFalse(cfg.contains("OTHER_VAR"))
    }

    func testFromEnvironmentCustomKeyTransform() {
        let env = ["APP_VccLower": "3.0"]
        let cfg = TestConfig.from(environment: env, prefix: "APP_", keyTransform: { $0 })
        XCTAssertEqual(cfg.double("VccLower"), 3.0)
    }

    func testFromEnvironmentSkipsEmptyKey() {
        // 仅"prefix"本身不带后缀应跳过
        let env = ["SWIFTHTF_": "x"]
        let cfg = TestConfig.from(environment: env, prefix: "SWIFTHTF_")
        XCTAssertTrue(cfg.values.isEmpty)
    }

    // MARK: - 命令行

    func testFromArgumentsBothForms() {
        let args = [
            "/path/to/program",
            "--vcc.lower", "3.0",
            "--vcc.upper=3.6",
            "--operator", "alice",
            "--retries=5",
        ]
        let cfg = TestConfig.from(arguments: args)
        XCTAssertEqual(cfg.double("vcc.lower"), 3.0)
        XCTAssertEqual(cfg.double("vcc.upper"), 3.6)
        XCTAssertEqual(cfg.string("operator"), "alice")
        XCTAssertEqual(cfg.int("retries"), 5)
    }

    func testFromArgumentsBareFlag() {
        let args = ["/x", "--enable-fast", "--retries=2"]
        let cfg = TestConfig.from(arguments: args)
        // 裸 flag → bool true
        XCTAssertEqual(cfg.bool("enable-fast"), true)
        XCTAssertEqual(cfg.int("retries"), 2)
    }

    func testFromArgumentsIgnoresLooseTokens() {
        let args = ["/x", "freeStanding", "--k=v"]
        let cfg = TestConfig.from(arguments: args)
        XCTAssertEqual(cfg.string("k"), "v")
        XCTAssertFalse(cfg.contains("freeStanding"))
    }

    // MARK: - 合并优先级

    func testMergingOverrideWins() {
        let a = TestConfig(values: ["k1": .int(1), "k2": .int(2)])
        let b = TestConfig(values: ["k2": .int(20), "k3": .int(30)])
        let merged = a.merging(b)
        XCTAssertEqual(merged.int("k1"), 1)
        XCTAssertEqual(merged.int("k2"), 20, "b 应覆盖 a")
        XCTAssertEqual(merged.int("k3"), 30)
    }

    func testMergingChainOpenHTFPriority() {
        // defaults < file < env < cli
        let defaults = TestConfig(values: ["vcc.lower": .double(3.0), "vcc.upper": .double(3.6)])
        let file = TestConfig(values: ["vcc.upper": .double(3.5)])
        let env = TestConfig(values: ["operator": .string("alice")])
        let cli = TestConfig(values: ["vcc.lower": .double(2.9)])
        let merged = defaults.merging(file).merging(env).merging(cli)
        XCTAssertEqual(merged.double("vcc.lower"), 2.9, "cli 最优先")
        XCTAssertEqual(merged.double("vcc.upper"), 3.5, "file 覆盖 defaults")
        XCTAssertEqual(merged.string("operator"), "alice")
    }

    // MARK: - 字符串类型推断

    func testStringValueTypeInference() {
        XCTAssertEqual(AnyCodableValue.from(stringValue: "true"), .bool(true))
        XCTAssertEqual(AnyCodableValue.from(stringValue: "False"), .bool(false))
        XCTAssertEqual(AnyCodableValue.from(stringValue: "42"), .int(42))
        XCTAssertEqual(AnyCodableValue.from(stringValue: "3.14"), .double(3.14))
        XCTAssertEqual(AnyCodableValue.from(stringValue: "abc"), .string("abc"))
        // 空字符串保留为 string
        XCTAssertEqual(AnyCodableValue.from(stringValue: ""), .string(""))
    }
}
