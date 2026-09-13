import SwiftUI
import SwiftData
import Charts
import HealthCore

/// The longevity-stack view: symptom episodes overlaid on environment (AQI)
/// and lifestyle (sleep) so the clustering is visible at a glance.
struct TrendsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \StoredEvent.timestamp) private var stored: [StoredEvent]
    @State private var metrics: [DailyMetrics] = []

    private var events: [HealthEvent] { stored.map(\.asHealthEvent) }

    private var insights: Insights { Insights(events: events, metrics: metrics) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let corr = insights.highAQICorrelation {
                        InsightCallout(text: aqiCalloutText(corr))
                    }

                    ChartCard(title: "Air quality & episodes", systemImage: "aqi.medium") {
                        aqiChart
                    }

                    ChartCard(title: "Sleep & episodes", systemImage: "bed.double") {
                        sleepChart
                    }

                    statsRow
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Trends")
            .task {
                if metrics.isEmpty {
                    metrics = await appEnvironment.loadDailyMetrics()
                }
            }
        }
    }

    /// Drops the base-rate clause when no daily AQI history exists to support it.
    private func aqiCalloutText(_ corr: Insights.AQICorrelation) -> String {
        let lead = "\(corr.onHighAQIDays) of \(corr.total) episodes happened on high-AQI days"
        guard let share = corr.highAQIDayShare else { return lead + "." }
        return lead + " — though only \(share)% of days were high-AQI."
    }

    private var aqiChart: some View {
        Chart {
            ForEach(metrics) { day in
                if let aqi = day.peakAQI {
                    LineMark(
                        x: .value("Day", day.date),
                        y: .value("AQI", aqi)
                    )
                    .foregroundStyle(Color.gray.opacity(0.55))
                    .interpolationMethod(.monotone)
                }
            }
            RuleMark(y: .value("Unhealthy", 100))
                .foregroundStyle(.red.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("AQI 100")
                        .font(.rounded(.caption2))
                        .foregroundStyle(.red.opacity(0.7))
                }
            ForEach(events) { event in
                if let aqi = event.environment?.aqi {
                    PointMark(
                        x: .value("Day", event.timestamp),
                        y: .value("AQI", aqi)
                    )
                    .foregroundStyle(Color.severity(event.severity))
                    .symbolSize(CGFloat(60 + event.severity * 14))
                }
            }
        }
        .chartYAxisLabel("US AQI")
        .frame(height: 190)
    }

    private var sleepChart: some View {
        Chart {
            ForEach(metrics) { day in
                if let sleep = day.sleepHours {
                    BarMark(
                        x: .value("Day", day.date),
                        y: .value("Hours", sleep.value)
                    )
                    .foregroundStyle(
                        sleep.value < 6
                            ? Color.orange.opacity(0.75)
                            : Color.brandTeal.opacity(0.45)
                    )
                }
            }
            ForEach(events) { event in
                PointMark(
                    x: .value("Day", event.timestamp),
                    y: .value("Hours", 9.3)
                )
                .foregroundStyle(Color.severity(event.severity))
                .symbolSize(50)
            }
            RuleMark(y: .value("Short sleep", 6))
                .foregroundStyle(.orange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYAxisLabel("Sleep (h) — dots are episodes")
        .frame(height: 170)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(value: "\(events.count)", label: "episodes")
            StatTile(value: String(format: "%.1f", insights.meanSeverity), label: "avg severity")
            StatTile(value: String(format: "%.1f", insights.episodesPerWeek), label: "per week")
        }
        // Carries how many days of lifestyle data the provider actually returned, so
        // tests can tell "HealthKit returned nothing" from "the chart just looks empty".
        // An invisible probe view can't be used: zero-size/zero-opacity views are
        // dropped from the accessibility tree entirely.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trends.stats")
        .accessibilityValue("metricDays:\(metrics.count)")
    }
}

struct InsightCallout: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.max.fill")
                .foregroundStyle(Color.brandTeal)
            Text(text)
                .font(.rounded(.callout, weight: .medium))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandTeal.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Color.brandTeal)
            content
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.rounded(.title2, weight: .bold))
                .foregroundStyle(Color.brandTeal)
            Text(label)
                .font(.rounded(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
