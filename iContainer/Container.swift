import Foundation

struct Container: Identifiable, Equatable {
    let id: String
    let name: String
    var status: ContainerStatus
    let image: String?
    let ipAddress: String?
    /// Networks the container is attached to (`configuration.networks[].network`).
    var networkNames: [String] = []
    /// Named volumes mounted into the container (`mounts[].type.volume.name`).
    var volumeNames: [String] = []
    /// Same volumes with their mount point inside the container.
    var volumeMounts: [VolumeMount] = []
}

struct VolumeMount: Equatable, Hashable {
    let name: String
    let destination: String
}

enum ContainerStatus: Equatable {
    case running
    case stopped
} 
