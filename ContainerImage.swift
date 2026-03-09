import Foundation

struct ContainerImage: Identifiable, Equatable {
    let id: String
    let name: String
    let tag: String?
    let sizeBytes: Int64?
    let sizeText: String?
    let createdAt: String?

    var reference: String {
        Self.reference(name: name, tag: tag)
    }

    var displayName: String {
        let ref = reference
        if !ref.isEmpty {
            return Self.shortName(from: ref)
        }
        let fallback = name.isEmpty ? id : name
        return Self.shortName(from: fallback)
    }

    var displaySize: String {
        if let sizeText, !sizeText.isEmpty {
            return sizeText
        }
        if let sizeBytes {
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
        return "-"
    }

    var displayCreated: String {
        createdAt ?? "-"
    }

    static func reference(name: String, tag: String?) -> String {
        guard !name.isEmpty else { return "" }
        if let tag, !tag.isEmpty, tag != "<none>" {
            return "\(name):\(tag)"
        }
        return name
    }

    static func shortName(from reference: String) -> String {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let parts = trimmed.split(separator: "/")
        return String(parts.last ?? Substring(trimmed))
    }
}
