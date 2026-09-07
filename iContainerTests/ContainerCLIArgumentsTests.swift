import XCTest
@testable import iContainer

/// Tests for the single `ContainerCreateSpec` → `container create` flag
/// builder shared by the create sheet, compose Up and the Docker clone flow.
final class ContainerCLIArgumentsTests: XCTestCase {

    func testMinimalSpecIsJustCreateAndImage() {
        let args = ContainerCLIArguments.create(ContainerCreateSpec(image: "alpine:latest"))
        XCTAssertEqual(args, ["create", "alpine:latest"])
    }

    func testFullSpecEmitsEveryFlagInFixedOrder() {
        let spec = ContainerCreateSpec(
            image: " nginx:1.25 ",
            name: "web",
            publishedPorts: ["8080:80", "8443:443/tcp"],
            volumes: ["/host:/data", "cache:/var/cache:ro"],
            environment: ["A=1", "B=2"],
            command: ["nginx", "-g", "daemon off;"],
            entrypoint: "/docker-entrypoint.sh",
            workingDirectory: "/srv",
            user: "1000:1000",
            cpus: 2,
            memoryBytes: 536_870_912,
            labels: ["com.example=1"],
            network: "app-net",
            capabilitiesToAdd: ["NET_ADMIN"],
            capabilitiesToDrop: ["ALL"],
            tmpfsPaths: ["/tmp"],
            readOnlyRootFilesystem: true
        )
        XCTAssertEqual(ContainerCLIArguments.create(spec), [
            "create",
            "--name", "web",
            "--network", "app-net",
            "--label", "com.example=1",
            "-e", "A=1", "-e", "B=2",
            "-p", "8080:80", "-p", "8443:443/tcp",
            "-v", "/host:/data", "-v", "cache:/var/cache:ro",
            "-w", "/srv",
            "-u", "1000:1000",
            "--entrypoint", "/docker-entrypoint.sh",
            "--cpus", "2",
            "--memory", "536870912",
            "--cap-add", "NET_ADMIN",
            "--cap-drop", "ALL",
            "--tmpfs", "/tmp",
            "--read-only",
            "nginx:1.25",
            "nginx", "-g", "daemon off;"
        ])
    }

    func testBlankEntriesAreDroppedAndValuesTrimmed() {
        let spec = ContainerCreateSpec(
            image: "img",
            name: "   ",
            publishedPorts: ["", " 80:80 "],
            volumes: [" "],
            environment: ["", "K=v "]
        )
        XCTAssertEqual(ContainerCLIArguments.create(spec), ["create", "-e", "K=v", "-p", "80:80", "img"])
    }

    func testZeroResourcesAreNotEmitted() {
        var spec = ContainerCreateSpec(image: "img")
        spec.cpus = 0
        spec.memoryBytes = 0
        XCTAssertEqual(ContainerCLIArguments.create(spec), ["create", "img"])
    }

    /// The compose Up path must produce the same flags it emitted before the
    /// spec refactor (order aside): name, network, label, env, ports,
    /// volumes, image, command.
    func testComposeServiceShapedSpec() {
        let spec = ContainerCreateSpec(
            image: "postgres:16",
            name: "demo-db",
            publishedPorts: ["5432:5432"],
            volumes: ["dbdata:/var/lib/postgresql/data"],
            environment: ["POSTGRES_PASSWORD=secret"],
            command: [],
            labels: ["com.icontainer.compose.project=demo"],
            network: "demo-net"
        )
        let args = ContainerCLIArguments.create(spec)
        XCTAssertEqual(args.first, "create")
        XCTAssertEqual(args.last, "postgres:16")
        XCTAssertTrue(args.contains("--network") && args.contains("demo-net"))
        XCTAssertTrue(args.contains("--label") && args.contains("com.icontainer.compose.project=demo"))
        XCTAssertTrue(args.contains("-v") && args.contains("dbdata:/var/lib/postgresql/data"))
    }
}
