import SwiftHTF
@testable import SwiftHTFCharts
import XCTest

/// 验证 `CustomLineChart` 内部分组 / 边界推断（不依赖 SwiftUI 渲染）。
final class CustomLineChartTests: XCTestCase {
    func testGroupCollapsesAllNilSeriesIntoSingleGroup() {
        let pts: [SeriesChartLayout.Point] = [
            .init(id: 0, x: 0, y: 0, series: nil),
            .init(id: 1, x: 1, y: 1, series: nil),
        ]
        let groups = CustomLineChart.group(points: pts)
        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].label)
        XCTAssertEqual(groups[0].points.count, 2)
    }

    func testGroupSplitsBySeriesLabelPreservingFirstSeenOrder() {
        let pts: [SeriesChartLayout.Point] = [
            .init(id: 0, x: 0, y: 0, series: "25"),
            .init(id: 1, x: 0, y: 0, series: "85"),
            .init(id: 2, x: 1, y: 1, series: "25"),
            .init(id: 3, x: 1, y: 1, series: "85"),
        ]
        let groups = CustomLineChart.group(points: pts)
        XCTAssertEqual(groups.map(\.label), ["25", "85"])
        XCTAssertEqual(groups[0].points.count, 2)
        XCTAssertEqual(groups[1].points.count, 2)
    }

    func testEmptyPointsProduceEmptyGroups() {
        XCTAssertTrue(CustomLineChart.group(points: []).isEmpty)
    }

    func testBoundsWithEmptyPointsFallsBackToUnitSquare() {
        let b = CustomLineChart.bounds(of: [], specRange: nil)
        XCTAssertEqual(b.xMin, 0); XCTAssertEqual(b.xMax, 1)
        XCTAssertEqual(b.yMin, 0); XCTAssertEqual(b.yMax, 1)
    }

    func testBoundsExpandSinglePointToAvoidDivByZero() {
        let p = SeriesChartLayout.Point(id: 0, x: 3.0, y: 1.5, series: nil)
        let b = CustomLineChart.bounds(of: [p], specRange: nil)
        XCTAssertLessThan(b.xMin, b.xMax)
        XCTAssertLessThan(b.yMin, b.yMax)
    }

    func testBoundsIncludeSpecRangeInY() {
        let pts: [SeriesChartLayout.Point] = [
            .init(id: 0, x: 0, y: 3.2, series: nil),
            .init(id: 1, x: 1, y: 3.3, series: nil),
        ]
        let b = CustomLineChart.bounds(of: pts, specRange: 2.5 ... 3.6)
        XCTAssertLessThanOrEqual(b.yMin, 2.5)
        XCTAssertGreaterThanOrEqual(b.yMax, 3.6)
    }
}
