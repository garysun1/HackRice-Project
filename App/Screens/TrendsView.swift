import SwiftUI
import SwiftData
import HealthCore

enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        }
    }
}

struct TrendsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \StoredEvent.timestamp) private var stored: [StoredEvent]
    @State private var metrics: [DailyMetrics] = []
    @State private var range: TrendRange = .month
    @State private var showingManualMetrics = false
    @State private var hasLoaded = false

    private let calendar = Calendar.current

    private var events: [HealthEvent] { stored.map(\.asHealthEvent) }
    private var insights: Insights { Insights(events: events, metrics: metrics) }
    private var windowEnd: Date { .now }
    private var windowStart: Date {
        calendar.date(
            byAdding: .day,
            value: -range.rawValue,
            to: calendar.startOfDay(for: .now)
        ) ?? .now
    }
    private var windowedMetrics: [DailyMetrics] {
        metrics.filter { $0.date >= windowStart }
    }
    private var windowedEvents: [HealthEvent] {
        events.filter { $0.timestamp >= windowStart }
    }
    private var useWeekly: Bool { range == .quarter }
    private var displayedSeries: [TrendSeries] {
        let ranked = insights.rankedSeries
        guard ranked.isEmpty else { return ranked }
        return TrendSeries.allCases.filter { series in
            metrics.contains { series.value(in: $0) != nil }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasLoaded && metrics.isEmpty && stored.isEmpty {
                        ContentUnavailableView {
                            Label("No data yet", systemImage: "chart.xyaxis.line")
                        } description: {
                            Text("Connect Apple Health or log an entry to start seeing trends.")
                        } actions: {
                            Button("Log daily metrics") {
                                showingManualMetrics = true
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("trends.empty")

                        statsRow
                    } else {
                        Picker("Range", selection: $range) {
                            ForEach(TrendRange.allCases) { range in
                                Text(range.label).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("trends.range")

                        if let correlation = insights.rankedCorrelations.first,
                           correlation.strength != .insufficient {
                            InsightCallout(text: correlation.calloutText)
                        }

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(displayedSeries) { series in
                                NavigationLink(value: series) {
                                    MetricTile(
                                        series: series,
                                        correlation: insights.correlation(for: series),
                                        metrics: windowedMetrics,
                                        weekly: useWeekly
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("trends.tile.\(series.id)")
                            }
                        }

                        statsRow
                    }
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Trends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingManualMetrics = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log daily metrics")
                    .accessibilityIdentifier("trends.add")
                }
            }
            .sheet(isPresented: $showingManualMetrics) {
                ManualMetricsView()
            }
            .navigationDestination(for: TrendSeries.self) { series in
                MetricDetailView(
                    series: series,
                    correlation: insights.correlation(for: series),
                    metrics: windowedMetrics,
                    events: windowedEvents,
                    weekly: useWeekly,
                    windowStart: windowStart,
                    windowEnd: windowEnd
                )
            }
            .task(id: appEnvironment.metricsVersion) {
                metrics = await appEnvironment.loadDailyMetrics()
                hasLoaded = true
            }
        }
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
