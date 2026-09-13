import SwiftUI
import SwiftData
import HealthCore

struct EpisodeEditorView: View {
    enum Mode {
        case create
        case edit(StoredEvent)
    }

    private enum DurationOption: String, CaseIterable, Identifiable {
        case none = "None"
        case fifteenMinutes = "15 min"
        case thirtyMinutes = "30 min"
        case oneHour = "1 h"
        case twoHours = "2 h"
        case custom = "Custom"

        var id: String { rawValue }

        var interval: TimeInterval? {
            switch self {
            case .none, .custom: nil
            case .fifteenMinutes: 15 * 60
            case .thirtyMinutes: 30 * 60
            case .oneHour: 60 * 60
            case .twoHours: 2 * 60 * 60
            }
        }
    }

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    @State private var symptom: String
    @State private var otherSymptom: String
    @State private var severity: Double
    @State private var timestamp: Date
    @State private var durationOption: DurationOption
    @State private var customDurationMinutes: String
    @State private var selectedMedications: Set<String>
    @State private var otherMedication: String
    @State private var selectedTags: Set<String>
    @State private var note: String

    private static let symptomLabels = MockIntelligence.symptomLexicon.map(\.label)
    private static let medicationLabels = MockIntelligence.medicationLexicon.map(\.label)
    private static let contextLabels = MockIntelligence.contextTags.map(\.tag)

    init(_ mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _symptom = State(initialValue: Self.symptomLabels.first ?? "general discomfort")
            _otherSymptom = State(initialValue: "")
            _severity = State(initialValue: 4)
            _timestamp = State(initialValue: Date())
            _durationOption = State(initialValue: .none)
            _customDurationMinutes = State(initialValue: "")
            _selectedMedications = State(initialValue: [])
            _otherMedication = State(initialValue: "")
            _selectedTags = State(initialValue: [])
            _note = State(initialValue: "")
        case .edit(let event):
            let knownSymptom = Self.symptomLabels.contains(event.symptom)
            let duration = Self.durationState(for: event.duration)
            let knownMedications = Set(event.medications.filter(Self.medicationLabels.contains))
            let otherMedications = event.medications.filter { !Self.medicationLabels.contains($0) }
            _symptom = State(initialValue: knownSymptom ? event.symptom : "Other")
            _otherSymptom = State(initialValue: knownSymptom ? "" : event.symptom)
            _severity = State(initialValue: Double(event.severity))
            _timestamp = State(initialValue: event.timestamp)
            _durationOption = State(initialValue: duration.option)
            _customDurationMinutes = State(initialValue: duration.minutes)
            _selectedMedications = State(initialValue: knownMedications)
            _otherMedication = State(initialValue: otherMedications.joined(separator: ", "))
            _selectedTags = State(initialValue: Set(event.tags))
            _note = State(initialValue: event.transcript)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Symptom") {
                    Picker("Symptom", selection: $symptom) {
                        ForEach(Self.symptomLabels, id: \.self) { label in
                            Text(label.capitalized).tag(label)
                        }
                        Text("Other").tag("Other")
                    }
                    .accessibilityIdentifier("episode.symptom")

                    if symptom == "Other" {
                        TextField("Symptom", text: $otherSymptom)
                    }
                }

                Section("Severity") {
                    HStack(spacing: 12) {
                        Slider(value: $severity, in: 1...10, step: 1)
                            .accessibilityIdentifier("episode.severity")
                        SeverityBadge(severity: Int(severity.rounded()))
                    }
                }

                Section("When") {
                    DatePicker(
                        "Date and time",
                        selection: $timestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Duration") {
                    Picker("Duration", selection: $durationOption) {
                        ForEach(DurationOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    if durationOption == .custom {
                        HStack {
                            TextField("Minutes", text: $customDurationMinutes)
                                .keyboardType(.numberPad)
                            Text("min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Medications") {
                    ForEach(Self.medicationLabels, id: \.self) { medication in
                        Toggle(medication, isOn: setBinding(medication, in: $selectedMedications))
                    }
                    TextField("Other medication", text: $otherMedication)
                }

                Section("Context") {
                    ForEach(Self.contextLabels, id: \.self) { tag in
                        Toggle(tag.capitalized, isOn: setBinding(tag, in: $selectedTags))
                    }
                }

                Section("Note") {
                    TextField("What happened?", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(resolvedSymptom.isEmpty)
                    .accessibilityIdentifier("episode.save")
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: "Log symptom"
        case .edit: "Edit symptom"
        }
    }

    private var resolvedSymptom: String {
        let value = symptom == "Other" ? otherSymptom : symptom
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedDuration: TimeInterval? {
        if durationOption == .custom {
            return Double(customDurationMinutes).map { $0 * 60 }
        }
        return durationOption.interval
    }

    private var resolvedMedications: [String] {
        var medications = Self.medicationLabels.filter(selectedMedications.contains)
        let other = otherMedication.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty { medications.append(other) }
        return medications
    }

    private func setBinding(_ value: String, in selection: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { enabled in
                if enabled {
                    selection.wrappedValue.insert(value)
                } else {
                    selection.wrappedValue.remove(value)
                }
            }
        )
    }

    private func save() async {
        let transcript = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventNote = transcript.isEmpty ? resolvedSymptom : transcript
        switch mode {
        case .create:
            var event = HealthEvent(
                timestamp: timestamp,
                symptom: resolvedSymptom,
                severity: Int(severity.rounded()),
                duration: resolvedDuration,
                tags: Self.contextLabels.filter(selectedTags.contains),
                medications: resolvedMedications,
                transcript: eventNote,
                source: .manual
            )
            if let snapshot = try? await appEnvironment.environmentService.currentSnapshot() {
                event.environment = snapshot
            }
            modelContext.insert(StoredEvent(from: event))
        case .edit(let event):
            event.timestamp = timestamp
            event.symptom = resolvedSymptom
            event.severity = Int(severity.rounded())
            event.duration = resolvedDuration
            event.tags = Self.contextLabels.filter(selectedTags.contains)
            event.medications = resolvedMedications
            event.transcript = eventNote
        }
        try? modelContext.save()
        dismiss()
    }

    private static func durationState(for interval: TimeInterval?) -> (
        option: DurationOption,
        minutes: String
    ) {
        switch interval {
        case nil: (.none, "")
        case 15 * 60: (.fifteenMinutes, "")
        case 30 * 60: (.thirtyMinutes, "")
        case 60 * 60: (.oneHour, "")
        case 2 * 60 * 60: (.twoHours, "")
        case let interval?: (.custom, String(Int((interval / 60).rounded())))
        }
    }
}
