import XCTest
@testable import SwiftHTF

final class ValidatorTests: XCTestCase {
    // MARK: - RangeValidator

    func testRangeValidatorInRange() {
        let v = RangeValidator(lower: 1.0, upper: 10.0)
        XCTAssertEqual(v.validate("5.0"), .pass)
    }

    func testRangeValidatorBelowLower() {
        let v = RangeValidator(lower: 1.0, upper: 10.0)
        if case .pass = v.validate("0.5") { XCTFail("应失败") }
    }

    func testRangeValidatorAboveUpper() {
        let v = RangeValidator(lower: 1.0, upper: 10.0)
        if case .pass = v.validate("11") { XCTFail("应失败") }
    }

    func testRangeValidatorOnlyLower() {
        let v = RangeValidator(lower: 0)
        XCTAssertEqual(v.validate("100"), .pass)
        if case .pass = v.validate("-1") { XCTFail("应失败") }
    }

    func testRangeValidatorOnlyUpper() {
        let v = RangeValidator(upper: 100)
        XCTAssertEqual(v.validate("50"), .pass)
        if case .pass = v.validate("101") { XCTFail("应失败") }
    }

    func testRangeValidatorHexValue() {
        let v = RangeValidator(lower: 0, upper: 255)
        XCTAssertEqual(v.validate("0xFF"), .pass)
        XCTAssertEqual(v.validate("0xff"), .pass)
        if case .pass = v.validate("0x100") { XCTFail("0x100 = 256 应失败") }
    }

    func testRangeValidatorHexLimits() {
        XCTAssertEqual(RangeValidator.parseNumber("0xff"), 255)
        XCTAssertEqual(RangeValidator.parseNumber("0x10"), 16)
        XCTAssertEqual(RangeValidator.parseNumber("3.14"), 3.14)
        XCTAssertNil(RangeValidator.parseNumber("abc"))
        XCTAssertNil(RangeValidator.parseNumber(""))
    }

    func testRangeValidatorRejectsNonNumeric() {
        let v = RangeValidator(lower: 0, upper: 100)
        if case .pass = v.validate("not a number") { XCTFail("应失败") }
    }

    // MARK: - EqualsValidator

    func testEqualsValidatorMatch() {
        let v = EqualsValidator("OK")
        XCTAssertEqual(v.validate("OK"), .pass)
    }

    func testEqualsValidatorMismatch() {
        let v = EqualsValidator("OK")
        if case .pass = v.validate("NG") { XCTFail("应失败") }
    }

    // MARK: - RegexValidator

    func testRegexValidatorMatch() {
        let v = RegexValidator("^[A-Z]{3}\\d{4}$")
        XCTAssertEqual(v.validate("ABC1234"), .pass)
    }

    func testRegexValidatorNoMatch() {
        let v = RegexValidator("^[A-Z]{3}\\d{4}$")
        if case .pass = v.validate("abc") { XCTFail("应失败") }
    }

    // MARK: - NotEmptyValidator

    func testNotEmptyValidator() {
        let v = NotEmptyValidator()
        XCTAssertEqual(v.validate("x"), .pass)
        if case .pass = v.validate("") { XCTFail("空字符串应失败") }
        if case .pass = v.validate("   \n") { XCTFail("纯空白应失败") }
    }
}

// 让 ValidationResult 可比较，方便 XCTAssertEqual 用
extension ValidationResult: Equatable {
    public static func == (lhs: ValidationResult, rhs: ValidationResult) -> Bool {
        switch (lhs, rhs) {
        case (.pass, .pass): return true
        case (.fail(let a), .fail(let b)): return a == b
        default: return false
        }
    }
}
