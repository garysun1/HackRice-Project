import SwiftUI
import Charts
import HealthCore

struct MetricDetailView: View {
    let series: TrendSeries
    let correlation: Correlation?
    let metrics: [DailyMetrics]
    let events: [HealthEvent]
    let weekly: Bool
    let windowStart: Date
    let windowEnd: Date

    private let axisLabelWidth: CGFloat = 40
    private var strength: Correlation.Strength { correlation?.strength ?? .insufficient }

    private var latestValue: Double? {
        metrics.reversed().compactMap { series.value(in: $0) }.first
    }

    private var daysWithValue: Int {
        metrics.filter { series.value(in: $0) != nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                ChartCard(title: series.displayName, systemImage: series.systemImage) {
                    mainChart

                    Text("Episodes")
                        .font(.rounded(.caption2))
                        .foregroundStyle(.secondary)

                    episodeRug
                }
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle(series.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(latestValue.map(series.formatted) ?? "—")
                .font(.rounded(.largeTitle, weight: .bold))

            HStack(spacing: 8) {
                if let correlation {
                    Text(correlation.conditionLabel)
                        .font(.rounded(.subheadline, weight: .semibold))
                }
                Chip(text: strength.badgeText, tint: Color.strength(strength))
            }

            if daysWithValue < metrics.count {
                Text("logged \(daysWithValue) of \(metrics.count) days")
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
            }

            if let correlation, correlation.strength != .insufficient {
                Text(correlation.calloutText)
                    .font(.rounded(.body))
            } else {
                Text("Not enough episodes with \(series.displayName.lowercased()) data to compare yet.")
                    .font(.rounded(.body))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mainChart: some View {
        Chart {
            if weekly {
                ForEach(Insights.weekly(metrics, series: series)) { point in
                    metricMark(date: point.weekStart, value: point.value)
                }
            } else {
                ForEach(metrics) { day in
                    if let value = series.value(in: day) {
                        metricMark(date: day.date, value: value)
                    }
                }
            }

            if let correlation,
               correlation.strength != .insufficient || correlation.thresholdKind == .clinical {
                RuleMark(y: .value("Threshold", correlation.threshold))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.strength(.moderate).opacity(0.7))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(correlation.conditionLabel)
                            .font(.rounded(.caption2))
                    }
            }
        }
        .chartXScale(domain: windowStart...windowEnd)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v, format: .number.precision(.fractionLength(0...1)))
                            .frame(width: axisLabelWidth, alignment: .trailing)
                    }
                }
            }
        }
        .frame(height: 240)
    }

    @ChartContentBuilder
    private func metricMark(date: Date, value: Double) -> some ChartContent {
        switch series.plotStyle {
        case .line:
            LineMark(
                x: .value("Day", date),
                y: .value(series.displayName, value)
            )
            .foregroundStyle(Color.brandTeal)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2))
        case .bar:
            BarMark(
                x: .value("Day", date, unit: weekly ? .weekOfYear : .day),
                y: .value(series.displayName, value)
            )
            .foregroundStyle(Color.brandTeal)
        }
    }

    private var episodeRug: some View {
        Chart(events) { event in
            PointMark(
                x: .value("Day", event.timestamp),
                y: .value("", 0)
            )
            .foregroundStyle(Color.chartSeverity(event.severity))
            .symbolSize(CGFloat(30 + (event.severity ?? 3) * 10))
        }
        .chartXScale(domain: windowStart...windowEnd)
        .chartYScale(domain: -1...1)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0]) { _ in
                AxisValueLabel { Text("").frame(width: axisLabelWidth) }
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 36)
        .accessibilityElement()
        .accessibilityIdentifier("trends.detail.rug")
        .accessibilityLabel("\(events.count) episodes")
    }
}
