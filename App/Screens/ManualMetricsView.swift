import SwiftUI
import HealthCore

struct ManualMetricsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var values: [MetricKind: String] = [:]
    @State private var errors: [MetricKind: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Day",
                        selection: $day,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                Section {
                    ForEach(MetricKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(kind.displayName)
                                Spacer()
                                TextField("—", text: binding(for: kind))
                                    .keyboardType(kind.allowsDecimal ? .decimalPad : .numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(minWidth: 70)
                                    .accessibilityIdentifier("manual.metric.\(kind.rawValue)")
                                Text(kind.unitLabel)
                                    .foregroundStyle(.secondary)
                            }
                            if let error = errors[kind] {
                                Text(error)
                                    .font(.rounded(.caption2))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("Daily metrics")
                } footer: {
                    if appEnvironment.isDemoMode {
                        Text("Demo mode: manual entries aren't shown")
                    }
                }
            }
            .navigationTitle("Manual entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("manual.save")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Delete day", role: .destructive) {
                        deleteDay()
                    }
                }
            }
            .onAppear(perform: loadValues)
            .onChange(of: day) { _, _ in loadValues() }
        }
    }

    private func binding(for kind: MetricKind) -> Binding<String> {
        Binding(
            get: { values[kind, default: ""] },
            set: {
                values[kind] = $0
                errors[kind] = nil
            }
        )
    }

    private func loadValues() {
        guard let local = appEnvironment.localMetrics else { return }
        let stored = local.values(on: day)
        values = Dictionary(uniqueKeysWithValues: stored.map { kind, value in
            let text = kind.allowsDecimal ? String(value) : String(Int(value.rounded()))
            return (kind, text)
        })
        errors = [:]
    }

    private func save() {
        guard let local = appEnvironment.localMetrics else { return }
        var validationErrors: [MetricKind: String] = [:]
        for kind in MetricKind.allCases {
            let text = values[kind, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                local.delete(day: day, kind: kind)
                continue
            }
            guard let value = Double(text), kind.inputRange.contains(value) else {
                validationErrors[kind] = "Enter \(kind.inputRange.lowerBound.formatted())–\(kind.inputRange.upperBound.formatted()) \(kind.unitLabel)"
                continue
            }
            local.upsert(day: day, kind: kind, value: value)
        }
        errors = validationErrors
        appEnvironment.recordLocalMetricsChanged()
        if validationErrors.isEmpty { dismiss() }
    }

    private func deleteDay() {
        guard let local = appEnvironment.localMetrics else { return }
        local.deleteAll(on: day)
        appEnvironment.recordLocalMetricsChanged()
        dismiss()
    }
}
