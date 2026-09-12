import Foundation
import EventKit

/// Finds an upcoming doctor appointment so the app can proactively offer a briefing.
protocol AppointmentProvider: Sendable {
    func nextAppointment() async -> Appointment?
}

struct Appointment: Sendable, Equatable {
    let title: String
    let date: Date
}

/// Real EventKit scan: any event in the next 14 days whose title looks medical.
final class CalendarAppointmentProvider: AppointmentProvider, @unchecked Sendable {
    private let store = EKEventStore()
    private static let keywords = ["dr.", "dr ", "doctor", "appointment", "clinic", "checkup", "check-up", "physician", "pulmonolog", "cardiolog"]

    func nextAppointment() async -> Appointment? {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else { return nil }

        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 14, to: start) else { return nil }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        return events
            .filter { event in
                let title = event.title?.lowercased() ?? ""
                return Self.keywords.contains { title.contains($0) }
            }
            .sorted { $0.startDate < $1.startDate }
            .first
            .map { Appointment(title: $0.title ?? "Doctor appointment", date: $0.startDate) }
    }
}

/// Demo-mode appointment: always "Dr. Chen" two days out, so the banner shows on stage.
struct DemoAppointmentProvider: AppointmentProvider {
    func nextAppointment() async -> Appointment? {
        let date = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
        return Appointment(title: "Dr. Chen — Pulmonology", date: date)
    }
}
