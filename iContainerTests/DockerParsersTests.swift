import XCTest
@testable import iContainer

/// Tests for `DockerParsers`: the Docker CLI JSON parsers (against real
/// captured output in `DockerFixtures`) and every Docker → `container`
/// translation rule (against small synthetic inspect payloads).
final class DockerParsersTests: XCTestCase {

    // MARK: - docker images

    func testParseImageListFromRealOutput() {
        let images = DockerParsers.parseImageList(DockerFixtures.imagesNDJSON)
        XCTAssertEqual(images.count, 8)
        let alpine = images.first
        XCTAssertEqual(alpine?.repository, "alpine")
        XCTAssertEqual(alpine?.tag, "latest")
        XCTAssertEqual(alpine?.reference, "alpine:latest")
        XCTAssertEqual(alpine?.imageID, "5b10f432ef3d")
        XCTAssertEqual(alpine?.sizeText, "13.6MB")
        XCTAssertEqual(alpine?.createdSince, "4 months ago")
        // One image ID tagged twice → two rows, two distinct ForEach ids.
        XCTAssertEqual(images.filter { $0.imageID == "5b10f432ef3d" }.count, 2)
        XCTAssertEqual(Set(images.map(\.id)).count, images.count)
    }

    func testParseImageListHandlesDanglingAndMalformedLines() {
        let output = """
        {"ID":"abc123","Repository":"\\u003cnone\\u003e","Tag":"\\u003cnone\\u003e","Size":"1MB"}
        not json
        {"ID":"def456","Repository":"myapp","Tag":"","Size":"2MB"}
        {"Repository":"no-id","Tag":"x"}
        """
        let images = DockerParsers.parseImageList(output)
        XCTAssertEqual(images.count, 2)
        XCTAssertNil(images[0].tag)
        XCTAssertNil(images[0].reference, "dangling images have no importable reference")
        XCTAssertNil(images[1].tag)
        XCTAssertEqual(DockerParsers.parseImageList(""), [])
    }

    // MARK: - docker ps

    func testParseContainerListFromRealOutput() {
        let containers = DockerParsers.parseContainerList(DockerFixtures.psNDJSON)
        XCTAssertEqual(containers.count, 5)
        let grafana = containers.first
        XCTAssertEqual(grafana?.id, "2cb3aced0180")
        XCTAssertEqual(grafana?.name, "grafana")
        XCTAssertEqual(grafana?.image, "grafana/grafana")
        XCTAssertEqual(grafana?.state, "exited")
        XCTAssertEqual(grafana?.isRunning, false)
        XCTAssertEqual(grafana?.platform, "linux/arm64")
        XCTAssertNotNil(grafana?.createdAt)
        XCTAssertEqual(containers.last?.image, "victoriametrics/victoria-metrics:latest")
    }

    func testParseContainerListTakesFirstOfMultipleNames() {
        let output = #"{"ID":"aaa","Names":"web,web-alias","Image":"nginx","State":"running","Status":"Up 2 hours"}"#
        let containers = DockerParsers.parseContainerList(output)
        XCTAssertEqual(containers.first?.name, "web")
        XCTAssertEqual(containers.first?.isRunning, true)
        XCTAssertNil(containers.first?.platform)
    }

    // MARK: - docker inspect

    func testParseInspectGrafana() throws {
        let inspect = try XCTUnwrap(DockerParsers.parseContainerInspect(DockerFixtures.inspectGrafana))
        XCTAssertTrue(inspect.id.hasPrefix("2cb3aced0180"))
        XCTAssertEqual(inspect.name, "grafana", "leading slash stripped")
        XCTAssertEqual(inspect.state, "exited")
        XCTAssertEqual(inspect.imageReference, "grafana/grafana")
        XCTAssertEqual(inspect.imageID?.hasPrefix("sha256:"), true)
        XCTAssertEqual(inspect.entrypoint, ["/run.sh"])
        XCTAssertEqual(inspect.command, [], "null Cmd → empty")
        XCTAssertEqual(inspect.workingDirectory, "/usr/share/grafana")
        XCTAssertEqual(inspect.user, "472")
        XCTAssertTrue(inspect.environment.contains { $0.hasPrefix("PATH=") })
        XCTAssertEqual(inspect.portBindings, [.init(containerPort: "3000/tcp", hostIP: "", hostPort: "3000")])
        XCTAssertEqual(inspect.mounts, [])
        XCTAssertEqual(inspect.memoryBytes, 0)
        XCTAssertEqual(inspect.nanoCPUs, 0)
        XCTAssertEqual(inspect.restartPolicy, "no")
        XCTAssertEqual(inspect.networkMode, "vm-net")
        XCTAssertEqual(inspect.networks, ["vm-net"])
        XCTAssertFalse(inspect.privileged)
    }

    func testParseInspectSnmpExporterBindMount() throws {
        let inspect = try XCTUnwrap(DockerParsers.parseContainerInspect(DockerFixtures.inspectSnmpExporter))
        XCTAssertEqual(inspect.name, "snmp-exporter")
        XCTAssertEqual(inspect.entrypoint, ["/bin/snmp_exporter"])
        XCTAssertEqual(inspect.command, ["--config.file=/etc/snmp_exporter/snmp.yml"])
        XCTAssertEqual(inspect.mounts.count, 1)
        XCTAssertEqual(inspect.mounts.first?.type, "bind")
        XCTAssertEqual(inspect.mounts.first?.source, "/Users/demo/docker-data/snmp-exporter/snmp.yml")
        XCTAssertEqual(inspect.mounts.first?.destination, "/etc/snmp_exporter/snmp.yml")
        XCTAssertEqual(inspect.mounts.first?.readWrite, true)
        XCTAssertEqual(inspect.portBindings.first?.hostPort, "9116")
    }

    func testParseInspectMalformed() {
        XCTAssertNil(DockerParsers.parseContainerInspect(""))
        XCTAssertNil(DockerParsers.parseContainerInspect("[]"))
        XCTAssertNil(DockerParsers.parseContainerInspect("{\"Name\":\"/x\"}"), "no Id")
        XCTAssertNil(DockerParsers.parseContainerInspect("nope"))
    }

    // MARK: - Translation (real fixtures)

    func testTranslateGrafana() throws {
        let inspect = try XCTUnwrap(DockerParsers.parseContainerInspect(DockerFixtures.inspectGrafana))
        let translation = DockerParsers.translate(inspect, imageEnvironment: inspect.environment)
        let spec = translation.spec
        XCTAssertEqual(spec.image, "grafana/grafana")
        XCTAssertEqual(spec.name, "grafana")
        XCTAssertEqual(spec.publishedPorts, ["3000:3000/tcp"])
        XCTAssertEqual(spec.volumes, [])
        XCTAssertEqual(spec.environment, [], "image defaults subtracted")
        XCTAssertEqual(spec.entrypoint, "/run.sh")
        XCTAssertEqual(spec.command, [])
        XCTAssertEqual(spec.workingDirectory, "/usr/share/grafana")
        XCTAssertEqual(spec.user, "472")
        XCTAssertNil(spec.cpus)
        XCTAssertNil(spec.memoryBytes)
        XCTAssertEqual(spec.network, "vm-net")
        XCTAssertEqual(translation.networkToCreate, "vm-net")
        XCTAssertEqual(spec.labels, ["com.icontainer.source=docker:2cb3aced0180"])
        XCTAssertEqual(translation.volumesToCreate, [])
        XCTAssertTrue(translation.warnings.isEmpty, "unexpected warnings: \(translation.warnings)")
    }

    func testTranslateGrafanaKeepsEnvironmentWhenNoImageEnvGiven() throws {
        let inspect = try XCTUnwrap(DockerParsers.parseContainerInspect(DockerFixtures.inspectGrafana))
        let translation = DockerParsers.translate(inspect)
        XCTAssertEqual(translation.spec.environment, inspect.environment)
    }

    func testTranslateSnmpExporter() throws {
        let inspect = try XCTUnwrap(DockerParsers.parseContainerInspect(DockerFixtures.inspectSnmpExporter))
        let spec = DockerParsers.translate(inspect).spec
        XCTAssertEqual(spec.volumes, ["/Users/demo/docker-data/snmp-exporter/snmp.yml:/etc/snmp_exporter/snmp.yml"])
        XCTAssertEqual(spec.entrypoint, "/bin/snmp_exporter")
        XCTAssertEqual(spec.command, ["--config.file=/etc/snmp_exporter/snmp.yml"])
        XCTAssertEqual(spec.publishedPorts, ["9116:9116/tcp"])
        let args = ContainerCLIArguments.create(spec)
        XCTAssertEqual(args.suffix(2), ["prom/snmp-exporter", "--config.file=/etc/snmp_exporter/snmp.yml"])
    }

    // MARK: - Translation rules (synthetic)

    private func inspect(config: String = "{}", hostConfig: String = "{}", mounts: String = "[]", networks: String = "{}") -> DockerContainerInspect {
        let json = """
        [{
          "Id": "0123456789abcdef",
          "Name": "/svc",
          "Image": "sha256:deadbeef",
          "State": {"Status": "running"},
          "Config": \(config),
          "HostConfig": \(hostConfig),
          "Mounts": \(mounts),
          "NetworkSettings": {"Networks": \(networks)}
        }]
        """
        return DockerParsers.parseContainerInspect(json)!
    }

    func testRandomHostPortFallsBackToContainerPortWithWarning() {
        let t = DockerParsers.translate(inspect(hostConfig: #"{"PortBindings":{"80/tcp":[{"HostIp":"","HostPort":""}]}}"#))
        XCTAssertEqual(t.spec.publishedPorts, ["80:80/tcp"])
        XCTAssertTrue(t.warnings.contains { $0.contains("random host port") })
    }

    func testSpecificHostIPIsPreservedAndWildcardsDropped() {
        let t = DockerParsers.translate(inspect(hostConfig: #"{"PortBindings":{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"15432"}],"53/udp":[{"HostIp":"0.0.0.0","HostPort":"53"}]}}"#))
        XCTAssertEqual(t.spec.publishedPorts, ["53:53/udp", "127.0.0.1:15432:5432/tcp"])
    }

    func testReadOnlyBindMountGetsRoSuffix() {
        let t = DockerParsers.translate(inspect(mounts: #"[{"Type":"bind","Source":"/host/cfg","Destination":"/etc/cfg","RW":false}]"#))
        XCTAssertEqual(t.spec.volumes, ["/host/cfg:/etc/cfg:ro"])
    }

    func testNamedVolumeIsMappedAndScheduledForCreation() {
        let t = DockerParsers.translate(inspect(mounts: #"[{"Type":"volume","Name":"dbdata","Source":"/var/lib/docker/volumes/dbdata/_data","Destination":"/var/lib/postgresql/data","RW":true}]"#))
        XCTAssertEqual(t.spec.volumes, ["dbdata:/var/lib/postgresql/data"])
        XCTAssertEqual(t.volumesToCreate, ["dbdata"])
        XCTAssertTrue(t.warnings.contains { $0.contains("dbdata") && $0.contains("not migrated") })
    }

    func testFractionalCPUsRoundUpWithWarningAndMemoryPassesThrough() {
        let t = DockerParsers.translate(inspect(hostConfig: #"{"NanoCpus":1500000000,"Memory":268435456}"#))
        XCTAssertEqual(t.spec.cpus, 2)
        XCTAssertEqual(t.spec.memoryBytes, 268_435_456)
        XCTAssertTrue(t.warnings.contains { $0.contains("rounded up to 2") })
    }

    func testWholeCPUsProduceNoWarning() {
        let t = DockerParsers.translate(inspect(hostConfig: #"{"NanoCpus":2000000000}"#))
        XCTAssertEqual(t.spec.cpus, 2)
        XCTAssertFalse(t.warnings.contains { $0.contains("rounded") })
    }

    func testMultiElementEntrypointMovesExtrasToCommand() {
        let t = DockerParsers.translate(inspect(config: #"{"Entrypoint":["/docker-entrypoint.sh","nginx"],"Cmd":["-g","daemon off;"]}"#))
        XCTAssertEqual(t.spec.entrypoint, "/docker-entrypoint.sh")
        XCTAssertEqual(t.spec.command, ["nginx", "-g", "daemon off;"])
    }

    func testEnvironmentSubtractionIsExactMatch() {
        let t = DockerParsers.translate(
            inspect(config: #"{"Env":["PATH=/usr/bin","APP_MODE=prod","PATH=/custom"]}"#),
            imageEnvironment: ["PATH=/usr/bin"]
        )
        XCTAssertEqual(t.spec.environment, ["APP_MODE=prod", "PATH=/custom"])
    }

    func testUnsupportedFeaturesProduceWarnings() {
        let t = DockerParsers.translate(inspect(
            config: #"{"Healthcheck":{"Test":["CMD","true"]}}"#,
            hostConfig: #"{"RestartPolicy":{"Name":"always"},"NetworkMode":"host","Privileged":true,"Devices":[{"PathOnHost":"/dev/x"}],"ExtraHosts":["db:10.0.0.2"],"Links":["db:db"],"DeviceRequests":[{"Driver":"nvidia"}]}"#
        ))
        let joined = t.warnings.joined(separator: "\n")
        for needle in ["Restart policy 'always'", "Host networking", "Privileged", "healthcheck", "device mapping", "extra_hosts", "Legacy links", "GPU"] {
            XCTAssertTrue(joined.contains(needle), "missing warning for \(needle): \(joined)")
        }
        XCTAssertNil(t.spec.network)
        XCTAssertNil(t.networkToCreate)
    }

    func testCapabilitiesTmpfsAndReadOnlyCarryOver() {
        let t = DockerParsers.translate(inspect(hostConfig: #"{"CapAdd":["NET_ADMIN"],"CapDrop":["ALL"],"Tmpfs":{"/run":"size=64m"},"ReadonlyRootfs":true}"#))
        XCTAssertEqual(t.spec.capabilitiesToAdd, ["NET_ADMIN"])
        XCTAssertEqual(t.spec.capabilitiesToDrop, ["ALL"])
        XCTAssertEqual(t.spec.tmpfsPaths, ["/run"])
        XCTAssertTrue(t.spec.readOnlyRootFilesystem)
    }

    func testMultipleUserNetworksKeepFirstAndWarn() {
        let t = DockerParsers.translate(inspect(hostConfig: #"{"NetworkMode":"front"}"#, networks: #"{"front":{},"back":{}}"#))
        XCTAssertEqual(t.spec.network, "back", "sorted alphabetically; deterministic")
        XCTAssertEqual(t.networkToCreate, "back")
        XCTAssertTrue(t.warnings.contains { $0.contains("2 Docker networks") })
    }

    func testBridgeNetworkIsNotRecreated() {
        let t = DockerParsers.translate(inspect(hostConfig: #"{"NetworkMode":"bridge"}"#, networks: #"{"bridge":{}}"#))
        XCTAssertNil(t.spec.network)
        XCTAssertNil(t.networkToCreate)
        XCTAssertTrue(t.warnings.isEmpty)
    }

    func testImageOverrideWins() {
        let t = DockerParsers.translate(inspect(config: #"{"Image":"redis:7"}"#), imageOverride: "docker.io/library/redis:7")
        XCTAssertEqual(t.spec.image, "docker.io/library/redis:7")
    }

    // MARK: - Reference normalisation

    func testNormalizedReference() {
        XCTAssertEqual(DockerParsers.normalizedReference("docker.io/library/alpine:latest"), "alpine:latest")
        XCTAssertEqual(DockerParsers.normalizedReference("index.docker.io/library/nginx"), "nginx:latest")
        XCTAssertEqual(DockerParsers.normalizedReference("library/redis:7"), "redis:7")
        XCTAssertEqual(DockerParsers.normalizedReference("docker.io/grafana/grafana"), "grafana/grafana:latest")
        XCTAssertEqual(DockerParsers.normalizedReference("alpine"), "alpine:latest")
        XCTAssertEqual(DockerParsers.normalizedReference("ghcr.io/org/img:1.2"), "ghcr.io/org/img:1.2")
        XCTAssertEqual(DockerParsers.normalizedReference("localhost:5000/app"), "localhost:5000/app:latest")
        XCTAssertEqual(DockerParsers.normalizedReference("  alpine:3.19 "), "alpine:3.19")
        XCTAssertEqual(DockerParsers.normalizedReference("alpine@sha256:abc"), "alpine@sha256:abc")
    }

    // MARK: - container image load output

    func testParseLoadedReferencesFiltersUntaggedManifests() {
        XCTAssertEqual(DockerParsers.parseLoadedReferences(DockerFixtures.loadOutput), ["docker.io/library/alpine:latest"])
        XCTAssertEqual(DockerParsers.parseLoadedReferences(""), [])
    }

    func testParseEnvironmentArray() {
        XCTAssertEqual(DockerParsers.parseEnvironmentArray(#"["PATH=/usr/bin","LANG=C"]"#), ["PATH=/usr/bin", "LANG=C"])
        XCTAssertEqual(DockerParsers.parseEnvironmentArray("null"), [])
        XCTAssertEqual(DockerParsers.parseEnvironmentArray(""), [])
    }
}
