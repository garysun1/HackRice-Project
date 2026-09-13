import SwiftUI
import Charts
import HealthCore

extension Correlation {
    var calloutText: String {
        switch series {
        case .airQuality:
            let lead = "\(hits) of \(total) episodes happened on high-AQI days"
            guard let dayShare else { return lead + "." }
            return lead + " — though only \(dayShare)% of days were high-AQI."
        case .metric(.sleepHours):
            let lead = "\(hits) of \(total) episodes followed nights with under 6h sleep"
            guard let dayShare else { return lead + "." }
            return lead + " — though only \(dayShare)% of nights were that short."
        case .metric:
            let relative = direction == .above ? "higher" : "lower"
            let comparison = direction == .above ? "above" : "below"
            let lead = "\(hits) of \(total) episodes happened on days with \(relative)-than-usual \(series.displayName.lowercased()) (\(comparison) your median of \(series.formatted(threshold)))"
            guard let dayShare else { return lead + "." }
            return lead + " — versus \(dayShare)% of days overall."
        }
    }

    var conditionLabel: String {
        let comparison = direction == .above ? "above" : "below"
        return switch series {
        case .airQuality:
            "AQI \(comparison) \(Int(threshold.rounded()))"
        default:
            "\(series.displayName) \(comparison) \(series.formatted(threshold))"
        }
    }
}

extension Correlation.Strength {
    var badgeText: String {
        switch self {
        case .strong: "Strong ●●●"
        case .moderate: "Moderate ●●○"
        case .weak: "Weak ●○○"
        case .insufficient: "Not enough data ○○○"
        }
    }
}

struct MetricTile: View {
    let series: TrendSeries
    let correlation: Correlation?
    let metrics: [DailyMetrics]
    let weekly: Bool

    private var strength: Correlation.Strength { correlation?.strength ?? .insufficient }

    private var latestValue: Double? {
        metrics.reversed().compactMap { series.value(in: $0) }.first
    }

    private var daysWithValue: Int {
        metrics.filter { series.value(in: $0) != nil }.count
    }

    private var markColor: Color {
        strength >= .moderate ? .brandTeal : Color(.systemGray2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(series.displayName, systemImage: series.systemImage)
                .font(.rounded(.caption, weight: .semibold))
                .lineLimit(1)

            Text(latestValue.map(series.formatted) ?? "—")
                .font(.rounded(.title3, weight: .bold))
                .lineLimit(1)

            sparkline

            Chip(text: strength.badgeText, tint: Color.strength(strength))

            Text("logged \(daysWithValue) of \(metrics.count) days")
                .font(.rounded(.caption2))
                .foregroundStyle(.secondary)
                .opacity(daysWithValue < metrics.count ? 1 : 0)
                .accessibilityHidden(daysWithValue >= metrics.count)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .opacity(strength >= .moderate ? 1 : 0.8)
        .accessibilityElement(children: .combine)
    }

    private var sparkline: some View {
        Chart {
            if weekly {
                ForEach(Insights.weekly(metrics, series: series)) { point in
                    mark(date: point.weekStart, value: point.value)
                }
            } else {
                ForEach(metrics) { day in
                    if let value = series.value(in: day) {
                        mark(date: day.date, value: value)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 44)
    }

    @ChartContentBuilder
    private func mark(date: Date, value: Double) -> some ChartContent {
        switch series.plotStyle {
        case .line:
            LineMark(
                x: .value("Day", date),
                y: .value(series.displayName, value)
            )
            .foregroundStyle(markColor)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2))
        case .bar:
            BarMark(
                x: .value("Day", date, unit: weekly ? .weekOfYear : .day),
                y: .value(series.displayName, value)
            )
            .foregroundStyle(markColor)
        }
    }
}
