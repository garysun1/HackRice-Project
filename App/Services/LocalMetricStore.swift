import Foundation
import SwiftData
import HealthCore

@MainActor
final class LocalMetricStore {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func entries(from start: Date, to end: Date) -> [ManualMetricEntry] {
        let descriptor = FetchDescriptor<StoredDailyMetric>(
            predicate: #Predicate { $0.day >= start && $0.day <= end },
            sortBy: [SortDescriptor(\.day)]
        )
        return ((try? context.fetch(descriptor)) ?? []).compactMap { stored in
            guard let kind = MetricKind(rawValue: stored.kindRaw) else { return nil }
            return ManualMetricEntry(day: stored.day, kind: kind, value: stored.value)
        }
    }

    func values(on day: Date) -> [MetricKind: Double] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [:] }
        return Dictionary(
            entries(from: start, to: end.addingTimeInterval(-1)).map { ($0.kind, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
    }

    func upsert(day: Date, kind: MetricKind, value: Double) {
        let day = calendar.startOfDay(for: day)
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<StoredDailyMetric>(
            predicate: #Predicate { $0.day == day && $0.kindRaw == kindRaw }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.value = value
        } else {
            context.insert(StoredDailyMetric(day: day, kindRaw: kindRaw, value: value))
        }
        try? context.save()
    }

    func delete(day: Date, kind: MetricKind) {
        let day = calendar.startOfDay(for: day)
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<StoredDailyMetric>(
            predicate: #Predicate { $0.day == day && $0.kindRaw == kindRaw }
        )
        for entry in (try? context.fetch(descriptor)) ?? [] {
            context.delete(entry)
        }
        try? context.save()
    }

    func deleteAll(on day: Date) {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<StoredDailyMetric>(
            predicate: #Predicate { $0.day >= start && $0.day < end }
        )
        for entry in (try? context.fetch(descriptor)) ?? [] {
            context.delete(entry)
        }
        try? context.save()
    }

    func allEntries() -> [ManualMetricEntry] {
        entries(from: .distantPast, to: .distantFuture)
    }
}
