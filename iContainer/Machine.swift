import Foundation

/// Lifecycle state of a container machine, as reported by
/// `container machine list/inspect`.
nonisolated enum MachineStatus: Equatable {
    case running
    case stopped
    case unknown

    init(cliValue: String?) {
        switch cliValue?.lowercased() {
        case "running": self = .running
        case "stopped": self = .stopped
        default: self = .unknown
        }
    }

    var isRunning: Bool { self == .running }
}

/// A container machine as shown in the sidebar list. Machines are identified
/// by their name (the CLI `id`).
nonisolated struct Machine: Identifiable, Equatable {
    let id: String
    let status: MachineStatus
    let cpus: Int?
    let memoryBytes: Int64?
    let diskBytes: Int64?
    let isDefault: Bool
    let createdDate: String?

    var name: String { id }
}

/// Detailed view of a single machine from `container machine inspect`.
nonisolated struct MachineDetails: Equatable {
    let id: String
    let status: MachineStatus
    let cpus: Int?
    let memoryBytes: Int64?
    let diskBytes: Int64?
    let homeMount: String?
    let imageReference: String?
    let os: String?
    let architecture: String?
    let createdDate: String?
    let username: String?
    let isDefault: Bool

    var name: String { id }
}
