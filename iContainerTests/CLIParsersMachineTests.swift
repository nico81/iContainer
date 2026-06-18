import XCTest
@testable import iContainer

/// Tests for `CLIParsers.parseMachineList` and `CLIParsers.parseMachineDetails`,
/// using JSON fixtures captured from the real `container machine` CLI (1.0.0).
final class CLIParsersMachineTests: XCTestCase {

    // MARK: - parseMachineList

    func testParseMachineListEmptyArray() {
        XCTAssertEqual(CLIParsers.parseMachineList("[]"), [])
    }

    func testParseMachineListMalformedReturnsEmpty() {
        XCTAssertEqual(CLIParsers.parseMachineList("not json"), [])
        XCTAssertEqual(CLIParsers.parseMachineList(""), [])
        XCTAssertEqual(CLIParsers.parseMachineList("{\"not\": \"array\"}"), [])
    }

    func testParseMachineListSingle() {
        let json = """
        [{"memory":12884901888,"cpus":4,"createdDate":"2026-06-18T14:33:12Z","id":"icprobe","status":"stopped","default":true,"diskSize":78610432}]
        """
        let machines = CLIParsers.parseMachineList(json)
        XCTAssertEqual(machines.count, 1)
        let m = machines[0]
        XCTAssertEqual(m.id, "icprobe")
        XCTAssertEqual(m.status, .stopped)
        XCTAssertEqual(m.cpus, 4)
        XCTAssertEqual(m.memoryBytes, 12_884_901_888)
        XCTAssertEqual(m.diskBytes, 78_610_432)
        XCTAssertTrue(m.isDefault)
        XCTAssertEqual(m.createdDate, "2026-06-18T14:33:12Z")
    }

    func testParseMachineListRunningAndNonDefault() {
        let json = """
        [{"id":"build","status":"running","cpus":2,"memory":2147483648,"diskSize":1024,"default":false}]
        """
        let machines = CLIParsers.parseMachineList(json)
        XCTAssertEqual(machines.count, 1)
        XCTAssertEqual(machines[0].status, .running)
        XCTAssertFalse(machines[0].isDefault)
    }

    func testParseMachineListSkipsItemsWithoutId() {
        let json = """
        [{"status":"stopped"}, {"id":"ok","status":"running"}]
        """
        let machines = CLIParsers.parseMachineList(json)
        XCTAssertEqual(machines.count, 1)
        XCTAssertEqual(machines[0].id, "ok")
    }

    func testParseMachineListUnknownStatus() {
        let json = """
        [{"id":"weird","status":"booting"}]
        """
        XCTAssertEqual(CLIParsers.parseMachineList(json).first?.status, .unknown)
    }

    // MARK: - parseMachineDetails

    func testParseMachineDetailsFromInspectArray() {
        let json = """
        [
          {
            "cpus" : 4,
            "createdDate" : "2026-06-18T14:33:12Z",
            "diskSize" : 78610432,
            "homeMount" : "rw",
            "id" : "icprobe",
            "image" : {
              "descriptor" : { "digest" : "sha256:310c", "mediaType" : "x", "size" : 9218 },
              "reference" : "docker.io/library/alpine:3.22"
            },
            "memory" : 12884901888,
            "platform" : { "architecture" : "arm64", "os" : "linux" },
            "status" : "stopped",
            "default" : true,
            "userSetup" : { "gid" : 20, "uid" : 501, "username" : "nico" }
          }
        ]
        """
        let d = CLIParsers.parseMachineDetails(json)
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.id, "icprobe")
        XCTAssertEqual(d?.status, .stopped)
        XCTAssertEqual(d?.cpus, 4)
        XCTAssertEqual(d?.memoryBytes, 12_884_901_888)
        XCTAssertEqual(d?.diskBytes, 78_610_432)
        XCTAssertEqual(d?.homeMount, "rw")
        XCTAssertEqual(d?.imageReference, "docker.io/library/alpine:3.22")
        XCTAssertEqual(d?.os, "linux")
        XCTAssertEqual(d?.architecture, "arm64")
        XCTAssertEqual(d?.username, "nico")
        XCTAssertTrue(d?.isDefault ?? false)
    }

    func testParseMachineDetailsFromBareObject() {
        let json = """
        {"id":"solo","status":"running","cpus":1}
        """
        let d = CLIParsers.parseMachineDetails(json)
        XCTAssertEqual(d?.id, "solo")
        XCTAssertEqual(d?.status, .running)
        XCTAssertEqual(d?.cpus, 1)
    }

    func testParseMachineDetailsMalformedReturnsNil() {
        XCTAssertNil(CLIParsers.parseMachineDetails("not json"))
        XCTAssertNil(CLIParsers.parseMachineDetails("[]"))
        XCTAssertNil(CLIParsers.parseMachineDetails("[{\"status\":\"running\"}]"))
    }
}
