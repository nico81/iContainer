import Foundation

struct Container: Identifiable {
    let id: String
    let name: String
    var status: ContainerStatus
    let image: String?
    let ipAddress: String?
}

enum ContainerStatus {
    case running
    case stopped
} 