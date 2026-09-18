import XCTest
@testable import iContainer

/// `container network/volume list --format json` parsers, against output
/// captured from CLI 1.4.1 (paths sanitised), plus the attachment
/// extraction used to relate containers to networks and volumes.
final class NetworkVolumeParserTests: XCTestCase {

    static let networksJSON = #"""
[{"configuration":{"creationDate":"2026-09-18T19:45:54Z","labels":{"com.apple.container.resource.role":"builtin"},"mode":"nat","name":"default","options":{},"plugin":"container-network-vmnet"},"id":"default","status":{"ipv4Gateway":"192.168.65.1","ipv4Subnet":"192.168.65.0/24","ipv6Subnet":"fd26:7379:c7a:dc84::/64"}},{"configuration":{"creationDate":"2026-09-07T07:54:32Z","labels":{},"mode":"nat","name":"desktop-net","options":{},"plugin":"container-network-vmnet"},"id":"desktop-net","status":{"ipv4Gateway":"192.168.64.1","ipv4Subnet":"192.168.64.0/24","ipv6Subnet":"fde3:b70b:cdf5:cca9::/64"}},{"configuration":{"creationDate":"2026-09-07T07:57:37Z","labels":{},"mode":"nat","name":"vm-net","options":{},"plugin":"container-network-vmnet"},"id":"vm-net","status":{"ipv4Gateway":"192.168.66.1","ipv4Subnet":"192.168.66.0/24","ipv6Subnet":"fd0b:5e5a:305d:f2ff::/64"}}]
"""#

    static let volumesJSON = #"""
[
 {
  "configuration": {
   "creationDate": "2026-03-09T20:26:24Z",
   "driver": "local",
   "format": "ext4",
   "labels": {
    "com.apple.container.resource.anonymous": ""
   },
   "name": "5e9277b0-1807-401e-8df8-d4e881dc9f50",
   "options": {},
   "sizeInBytes": 549755813888,
   "source": "/Users/demo/Library/Application Support/com.apple.container/volumes/5e9277b0-1807-401e-8df8-d4e881dc9f50/volume.img"
  },
  "id": "5e9277b0-1807-401e-8df8-d4e881dc9f50"
 },
 {
  "configuration": {
   "creationDate": "2026-03-09T20:26:24Z",
   "driver": "local",
   "format": "ext4",
   "labels": {},
   "name": "pgdata",
   "options": {},
   "sizeInBytes": 10737418240,
   "source": "/Users/demo/Library/Application Support/com.apple.container/volumes/pgdata/volume.img"
  },
  "id": "pgdata"
 }
]
"""#

    func testParseNetworkList() {
        let networks = CLIParsers.parseNetworkList(Self.networksJSON)
        XCTAssertEqual(networks.count, 3)
        let def = networks.first { $0.name == "default" }
        XCTAssertNotNil(def)
        XCTAssertTrue(def!.isBuiltin)
        XCTAssertEqual(def?.mode, "nat")
        XCTAssertEqual(def?.plugin, "container-network-vmnet")
        XCTAssertEqual(def?.ipv4Subnet, "192.168.65.0/24")
        XCTAssertEqual(def?.ipv4Gateway, "192.168.65.1")
        XCTAssertEqual(def?.ipv6Subnet, "fd26:7379:c7a:dc84::/64")
        XCTAssertEqual(def?.labels["com.apple.container.resource.role"], "builtin")
        let user = networks.first { $0.name == "vm-net" }
        XCTAssertEqual(user?.isBuiltin, false)
        XCTAssertNotNil(user?.creationDate)
    }

    func testParseVolumeList() {
        let volumes = CLIParsers.parseVolumeList(Self.volumesJSON)
        XCTAssertEqual(volumes.count, 2)
        let anon = volumes[0]
        XCTAssertTrue(anon.isAnonymous)
        XCTAssertEqual(anon.driver, "local")
        XCTAssertEqual(anon.format, "ext4")
        XCTAssertEqual(anon.capacityBytes, 549_755_813_888)
        XCTAssertTrue(anon.displayName.hasSuffix("…"), "anonymous UUID names are shortened")
        XCTAssertEqual(anon.source?.hasSuffix("/volume.img"), true)
        let named = volumes[1]
        XCTAssertEqual(named.name, "pgdata")
        XCTAssertFalse(named.isAnonymous)
        XCTAssertEqual(named.displayName, "pgdata")
        XCTAssertEqual(named.displayCapacity, ByteCountFormatter.string(fromByteCount: 10_737_418_240, countStyle: .file))
    }

    func testParseListsMalformed() {
        XCTAssertEqual(CLIParsers.parseNetworkList(""), [])
        XCTAssertEqual(CLIParsers.parseNetworkList("{}"), [])
        XCTAssertEqual(CLIParsers.parseVolumeList("nope"), [])
        XCTAssertEqual(CLIParsers.parseVolumeList("[{\"configuration\": {}}]"), [], "entries without a name are dropped")
    }

    func testParseContainerAttachments() {
        let entry: [String: Any] = [
            "configuration": [
                "id": "db",
                "networks": [["network": "app-net", "options": ["hostname": "db"]]],
                "mounts": [
                    ["type": ["volume": ["name": "pgdata", "format": "ext4"]], "source": "/x/volume.img", "destination": "/var/lib/postgresql/data"],
                    ["type": ["virtiofs": [:]], "source": "/Users/demo/cfg", "destination": "/etc/cfg"],
                    ["type": ["tmpfs": [:]], "source": "", "destination": "/run"]
                ]
            ]
        ]
        let attachments = CLIParsers.parseContainerAttachments(entry)
        XCTAssertEqual(attachments.networks, ["app-net"])
        XCTAssertEqual(attachments.volumes, ["pgdata"], "bind and tmpfs mounts are not volumes")
        let empty = CLIParsers.parseContainerAttachments(["configuration": ["id": "x"]])
        XCTAssertEqual(empty.networks, [])
        XCTAssertEqual(empty.volumes, [])
    }
}
