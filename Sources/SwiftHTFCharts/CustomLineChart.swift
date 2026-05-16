import Foundation
import SwiftHTF
import SwiftUI

/// macOS 12 / iOS 15 上 ``SeriesChart`` 的 fallback 实现 —— 纯 SwiftUI `Path` 自绘。
///
/// 不依赖 Apple `Charts` framework；牺牲交互（无 zoom / 无 tooltip）换来低系统版本兼容。
/// macOS 13+ / iOS 16+ 上 `SeriesChart` 会自动改用 Apple Charts 路径，不会触达此实现。
///
/// 行为：
/// - 1D / 2D / 0D layout 与 Apple Charts 路径完全一致（共用 `SeriesChartLayout` 投影）
/// - 2D：按第二个 dim 自动分组，每组一条线，按预定调色板循环上色
/// - spec 范围带：水平虚线 RuleMark 等价物（两条横线 + 半透明填充带）
/// - 轴：4 段 grid + 端点数值标签；不做自适应 tick（避免重新发明 NumberFormatter 全栈）
public struct CustomLineChart: View {
    private let trace: SeriesMeasurement
    private let specRange: ClosedRange<Double>?
    private let xLabel: String
    private let yLabel: String
    private let showLegend: Bool

    init(
        trace: SeriesMeasurement,
        specRange: ClosedRange<Double>?,
        xLabel: String,
        yLabel: String,
        showLegend: Bool
    ) {
        self.trace = trace
        self.specRange = specRange
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.showLegend = showLegend
    }

    public var body: some View {
        let points = SeriesChartLayout.points(from: trace)
        let groups = Self.group(points: points)
        let bounds = Self.bounds(of: points, specRange: specRange)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                yAxisLabels(bounds: bounds)
                GeometryReader { geo in
                    canvas(groups: groups, bounds: bounds, size: geo.size)
                }
            }
            xAxisFooter(bounds: bounds)
            if showLegend && groups.count > 1 {
                legend(groups: groups)
            }
        }
    }

    @ViewBuilder
    private func canvas(groups: [Group], bounds: Bounds, size: CGSize) -> some View {
        ZStack {
            gridBackground(size: size)
            specBand(size: size, bounds: bounds)
            ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                linePath(points: group.points, bounds: bounds, size: size)
                    .stroke(color(for: idx, count: groups.count), lineWidth: 1.5)
            }
        }
    }

    private func linePath(points: [SeriesChartLayout.Point], bounds: Bounds, size: CGSize) -> Path {
        var path = Path()
        for (i, p) in points.enumerated() {
            let pt = project(p, bounds: bounds, size: size)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }

    private func project(_ p: SeriesChartLayout.Point, bounds: Bounds, size: CGSize) -> CGPoint {
        let xFrac = bounds.xSpan == 0 ? 0.5 : (p.x - bounds.xMin) / bounds.xSpan
        let yFrac = bounds.ySpan == 0 ? 0.5 : (p.y - bounds.yMin) / bounds.ySpan
        return CGPoint(
            x: CGFloat(xFrac) * size.width,
            y: size.height - CGFloat(yFrac) * size.height
        )
    }

    private func gridBackground(size: CGSize) -> some View {
        Path { path in
            for i in 0 ... 4 {
                let y = CGFloat(i) / 4 * size.height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for i in 0 ... 4 {
                let x = CGFloat(i) / 4 * size.width
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
    }

    @ViewBuilder
    private func specBand(size: CGSize, bounds: Bounds) -> some View {
        if let range = specRange, bounds.ySpan > 0 {
            let loFrac = (range.lowerBound - bounds.yMin) / bounds.ySpan
            let hiFrac = (range.upperBound - bounds.yMin) / bounds.ySpan
            let loY = size.height - CGFloat(loFrac) * size.height
            let hiY = size.height - CGFloat(hiFrac) * size.height
            let bandTop = min(loY, hiY)
            let bandHeight = abs(loY - hiY)
            Rectangle()
                .fill(traceColor.opacity(0.08))
                .frame(width: size.width, height: bandHeight)
                .position(x: size.width / 2, y: bandTop + bandHeight / 2)
            Path { path in
                path.move(to: CGPoint(x: 0, y: loY)); path.addLine(to: CGPoint(x: size.width, y: loY))
                path.move(to: CGPoint(x: 0, y: hiY)); path.addLine(to: CGPoint(x: size.width, y: hiY))
            }
            .stroke(traceColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    private func yAxisLabels(bounds: Bounds) -> some View {
        VStack {
            Text(format(bounds.yMax)).font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text(yLabel).font(.caption2).bold().rotationEffect(.degrees(-90)).fixedSize()
            Spacer()
            Text(format(bounds.yMin)).font(.caption2).foregroundColor(.secondary)
        }
        .frame(width: 32)
    }

    private func xAxisFooter(bounds: Bounds) -> some View {
        HStack {
            Text(format(bounds.xMin)).font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text(xLabel).font(.caption2).bold()
            Spacer()
            Text(format(bounds.xMax)).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.leading, 36)
    }

    private func legend(groups: [Group]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.offset) { idx, g in
                HStack(spacing: 4) {
                    Circle().fill(color(for: idx, count: groups.count)).frame(width: 8, height: 8)
                    Text(g.label ?? "series \(idx)").font(.caption2)
                }
            }
            Spacer()
        }
        .padding(.leading, 36)
    }

    private func color(for index: Int, count: Int) -> Color {
        if count <= 1 { return traceColor }
        let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .brown]
        return palette[index % palette.count]
    }

    private var traceColor: Color {
        switch trace.outcome {
        case .pass: .green
        case .marginalPass: .yellow
        case .skip: .gray
        case .fail, .error, .timeout: .red
        }
    }

    private func format(_ v: Double) -> String {
        if abs(v) >= 1000 || (abs(v) < 0.01 && v != 0) {
            return String(format: "%.2e", v)
        }
        return String(format: "%.2f", v)
    }
}

// MARK: - 内部辅助类型 / 工具

extension CustomLineChart {
    struct Group {
        let label: String?
        let points: [SeriesChartLayout.Point]
    }

    struct Bounds {
        let xMin: Double
        let xMax: Double
        let yMin: Double
        let yMax: Double
        var xSpan: Double { xMax - xMin }
        var ySpan: Double { yMax - yMin }
    }

    /// 按 `series` 标签把点列表拆成多组。无标签的点全部归入单一组（label = nil）。
    static func group(points: [SeriesChartLayout.Point]) -> [Group] {
        if points.allSatisfy({ $0.series == nil }) {
            return points.isEmpty ? [] : [Group(label: nil, points: points)]
        }
        var order: [String] = []
        var buckets: [String: [SeriesChartLayout.Point]] = [:]
        for p in points {
            let key = p.series ?? ""
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(p)
        }
        return order.map { Group(label: $0.isEmpty ? nil : $0, points: buckets[$0] ?? []) }
    }

    /// 计算 X / Y 边界；spec 范围会被纳入 Y 轴避免超界。空数据用 [0,1] 兜底，
    /// 单点 / 退化区间在维度方向 pad 5% 防止除零。
    static func bounds(of points: [SeriesChartLayout.Point], specRange: ClosedRange<Double>?) -> Bounds {
        guard !points.isEmpty else {
            return Bounds(xMin: 0, xMax: 1, yMin: 0, yMax: 1)
        }
        let xs = points.map(\.x)
        var ys = points.map(\.y)
        if let r = specRange { ys.append(r.lowerBound); ys.append(r.upperBound) }
        var xMin = xs.min() ?? 0, xMax = xs.max() ?? 1
        var yMin = ys.min() ?? 0, yMax = ys.max() ?? 1
        if xMin == xMax { xMin -= 0.5; xMax += 0.5 }
        if yMin == yMax {
            let pad = max(abs(yMin) * 0.05, 0.5)
            yMin -= pad; yMax += pad
        }
        return Bounds(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax)
    }
}
