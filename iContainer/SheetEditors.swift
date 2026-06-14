import SwiftUI

/// Reusable building blocks for the "Create container" and "Edit container"
/// sheets owned by `ContentView`. They are intentionally generic so the same
/// component renders both flows (ports, volumes, env vars) — see the
/// `MappingPairsEditor` documentation below.

// MARK: - File / folder picker row

/// A labelled text field paired with a "browse" button. Used for the
/// Dockerfile / build-context pickers in the create sheet.
struct PathPickerRow: View {
    let title: String
    let placeholder: String
    @Binding var path: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField(placeholder, text: $path)
                    .textFieldStyle(.roundedBorder)
                Button(action: action) {
                    Image(systemName: systemImage)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .help("Choose \(title.lowercased())")
            }
        }
    }
}

// MARK: - Generic key/value mapping editor

/// Renders a list of `first:second` mappings plus an "add new" row. Used
/// for both ports (`host:container`) and volumes (`hostPath:containerPath`).
///
/// Storage is a comma- or newline-separated string in `mappingsText`; the
/// caller is responsible for appending/removing items via `addAction` /
/// `removeAction`. The view never mutates the text directly.
struct MappingPairsEditor: View {
    let title: String
    @Binding var mappingsText: String
    @Binding var firstValue: String
    @Binding var secondValue: String
    let isLoading: Bool
    let emptyText: String
    let firstTitle: String
    let secondTitle: String
    let firstPlaceholder: String
    let secondPlaceholder: String
    let formatText: String
    let iconName: String
    let addAction: () -> Void
    let removeAction: (String) -> Void
    let browseFirstAction: (() -> Void)?

    private var mappings: [String] {
        mappingsText
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, count: mappings.count)

            if mappings.isEmpty {
                Text(isLoading ? "Loading..." : emptyText)
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(mappings, id: \.self) { mapping in
                        let pair = splitMapping(mapping)
                        MappingRow(
                            iconName: iconName,
                            firstTitle: firstTitle,
                            firstValue: pair.first,
                            secondTitle: secondTitle,
                            secondValue: pair.second,
                            separator: ":",
                            removeAction: { removeAction(mapping) }
                        )
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                TextField(firstPlaceholder, text: $firstValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                if let browseFirstAction {
                    Button {
                        browseFirstAction()
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.bordered)
                    .help("Choose file or folder")
                }
                Text(":")
                    .foregroundColor(.secondary)
                TextField(secondPlaceholder, text: $secondValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    addAction()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Add \(title.lowercased())")
                .disabled(firstValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secondValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(formatText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func splitMapping(_ mapping: String) -> (first: String, second: String) {
        let parts = mapping.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return (mapping, "")
        }
        return (String(parts[0]), String(parts[1]))
    }
}

// MARK: - Environment variables editor

/// Sibling of `MappingPairsEditor` specialised for `KEY=VALUE` env vars.
/// The split character is `=` instead of `:`.
struct EnvironmentVariablesEditor: View {
    @Binding var environmentText: String
    @Binding var key: String
    @Binding var value: String
    let isLoading: Bool
    let emptyText: String
    let addAction: () -> Void
    let removeAction: (String) -> Void

    private var variables: [String] {
        environmentText
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Environment Variables", count: variables.count)

            if variables.isEmpty {
                Text(isLoading ? "Loading..." : emptyText)
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(variables, id: \.self) { variable in
                        let pair = splitVariable(variable)
                        MappingRow(
                            iconName: "textformat",
                            firstTitle: "Variable",
                            firstValue: pair.key,
                            secondTitle: "Value",
                            secondValue: pair.value,
                            separator: "=",
                            removeAction: { removeAction(variable) }
                        )
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                TextField("Variable", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Text("=")
                    .foregroundColor(.secondary)
                TextField("Value", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    addAction()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Add environment variable")
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func splitVariable(_ variable: String) -> (key: String, value: String) {
        let parts = variable.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return (variable, "")
        }
        return (String(parts[0]), String(parts[1]))
    }
}

// MARK: - Small shared chrome

/// Section header used by both editors above: a title with an optional
/// item count pill on the right.
struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            Spacer()
        }
    }
}

/// A single existing-mapping row with two labelled values and a delete
/// button. The `separator` is shown between the two columns (`:` or `=`).
struct MappingRow: View {
    let iconName: String
    let firstTitle: String
    let firstValue: String
    let secondTitle: String
    let secondValue: String
    let separator: String
    let removeAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .padding(.top, 12)
            MappingValueColumn(title: firstTitle, value: firstValue)
            Text(separator)
                .foregroundColor(.secondary)
                .font(.callout.monospaced())
                .padding(.top, 22)
            MappingValueColumn(title: secondTitle, value: secondValue)
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .padding(.top, 12)
            .help("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }
}

/// A "title + monospaced value" column. Renders `-` when the value is
/// empty so rows never collapse to zero height.
struct MappingValueColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
