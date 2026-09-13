import SwiftUI
import HealthCore

/// Level 3: exactly what one source has imported into Interim.
///
/// Every number here is derived from the data itself — day counts, date spans and latest
/// readings — rather than inferred from the source's name.
struct SourceDetailView: View {
    let source: SourceContribution

    var body: some View {
        List {
            Section {
                ForEach(source.dataTypes) { contribution in
                    DataTypeRow(contribution: contribution)
                        .accessibilityIdentifier("connections.detail.\(contribution.id)")
                }
            } header: {
                Text("Imported data")
            } footer: {
                Text(footerText)
            }
        }
        .navigationTitle(source.sourceName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footerText: String {
        let types = source.dataTypes.count
        let noun = types == 1 ? "data type" : "data types"
        return "\(source.sourceName) contributes \(types) \(noun) across \(source.totalDays) days. Interim reads this from Apple Health — it never contacts \(source.sourceName) directly."
    }
}

struct DataTypeRow: View {
    let contribution: DataTypeContribution

    private var span: String? {
        guard let first = contribution.firstDay, let last = contribution.lastDay else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: contribution.kind.systemImage)
                .font(.system(size: 15))
                .foregroundStyle(Color.brandTeal)
                .frame(width: 30, height: 30)
                .background(Color.brandTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(contribution.kind.displayName)
                    .font(.rounded(.body, weight: .medium))

                HStack(spacing: 6) {
                    Chip(text: "\(contribution.dayCount) days", tint: .brandTeal)
                    if let span {
                        Text(span)
                            .font(.rounded(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let latest = contribution.formattedLatest {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(latest)
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                    Text("latest")
                        .font(.rounded(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
