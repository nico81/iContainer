import XCTest
@testable import iContainer

/// Tests for `ComposeParser`, covering the compose-file YAML subset this
/// MVP supports: a minimal service, list/map forms of ports/environment/
/// volumes, `depends_on` ordering (including cycles and unknown names),
/// unsupported-directive detection, and malformed input.
final class ComposeParserTests: XCTestCase {

    // MARK: - Minimal service

    func testMinimalService() {
        let yaml = """
        services:
          web:
            image: nginx:latest
        """
        let parsed = ComposeParser.parse(yaml)
        XCTAssertEqual(parsed?.services.count, 1)
        let web = parsed?.services.first
        XCTAssertEqual(web?.name, "web")
        XCTAssertEqual(web?.image, "nginx:latest")
        XCTAssertEqual(web?.resolvedContainerName(project: "demo"), "demo-web")
        XCTAssertEqual(parsed?.ignoredDirectives, [])
    }

    func testEmptyServicesMapIsValidNotMalformed() {
        let yaml = """
        services:
        """
        let parsed = ComposeParser.parse(yaml)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.services, [])
    }

    func testContainerNameOverridesConvention() {
        let yaml = """
        services:
          web:
            image: nginx
            container_name: my-custom-name
        """
        let parsed = ComposeParser.parse(yaml)
        XCTAssertEqual(parsed?.services.first?.containerName, "my-custom-name")
        XCTAssertEqual(parsed?.services.first?.resolvedContainerName(project: "demo"), "my-custom-name")
    }

    func testQuotedImageValue() {
        let yaml = """
        services:
          web:
            image: "nginx:1.25"
        """
        XCTAssertEqual(ComposeParser.parse(yaml)?.services.first?.image, "nginx:1.25")
    }

    // MARK: - Ports / environment / volumes

    func testPortsListForm() {
        let yaml = """
        services:
          web:
            image: nginx
            ports:
              - "8080:80"
              - 9090:90
        """
        XCTAssertEqual(ComposeParser.parse(yaml)?.services.first?.ports, ["8080:80", "9090:90"])
    }

    func testPortsInlineArrayForm() {
        let yaml = """
        services:
          web:
            image: nginx
            ports: ["8080:80", "9090:90"]
        """
        XCTAssertEqual(ComposeParser.parse(yaml)?.services.first?.ports, ["8080:80", "9090:90"])
    }

    func testEnvironmentListForm() {
        let yaml = """
        services:
          web:
            image: nginx
            environment:
              - FOO=bar
              - BAZ=qux
        """
        XCTAssertEqual(ComposeParser.parse(yaml)?.services.first?.environment, ["FOO=bar", "BAZ=qux"])
    }

    func testEnvironmentMapForm() {
        let yaml = """
        services:
          web:
            image: nginx
            environment:
              FOO: bar
              BAZ: qux
        """
        XCTAssertEqual(ComposeParser.parse(yaml)?.services.first?.environment, ["FOO=bar", "BAZ=qux"])
    }

    func testVolumesListForm() {
        let yaml = """
        services:
          web:
            image: nginx
            volumes:
              - ./src:/usr/share/nginx/html
              - /abs/host:/abs/container
        """
        XCTAssertEqual(
            ComposeParser.parse(yaml)?.services.first?.volumes,
            ["./src:/usr/share/nginx/html", "/abs/host:/abs/container"]
        )
    }

    // MARK: - Command

    func testCommandScalarForm() {
        let yaml = """
        services:
          web:
            image: nginx
            command: npm start
        """
        XCTAssertEqual(ComposeParser.parse(yaml)?.services.first?.command, ["npm", "start"])
    }

    func testCommandInlineArrayForm() {
        let yaml = """
        services:
          web:
            image: nginx
            command: ["npm", "run", "start"]
        """
        XCTAssertEqual(ComposeParser.parse(yaml)?.services.first?.command, ["npm", "run", "start"])
    }

    func testCommandListForm() {
        let yaml = """
        services:
          web:
            image: nginx
            command:
              - bundle
              - exec
              - puma
        """
        XCTAssertEqual(ComposeParser.parse(yaml)?.services.first?.command, ["bundle", "exec", "puma"])
    }

    // MARK: - depends_on ordering

    func testDependsOnOrdering() {
        let yaml = """
        services:
          web:
            image: nginx
            depends_on:
              - db
              - cache
          db:
            image: postgres
          cache:
            image: redis
        """
        let parsed = ComposeParser.parse(yaml)!
        let ordered = ComposeParser.topologicalOrder(parsed.services)
        let names = ordered.map(\.name)
        XCTAssertEqual(Set(names), Set(["web", "db", "cache"]))
        XCTAssertLessThan(names.firstIndex(of: "db")!, names.firstIndex(of: "web")!)
        XCTAssertLessThan(names.firstIndex(of: "cache")!, names.firstIndex(of: "web")!)
    }

    func testDependsOnUnknownServiceIgnored() {
        let services = [
            ComposeService(name: "web", dependsOn: ["missing"])
        ]
        let ordered = ComposeParser.topologicalOrder(services)
        XCTAssertEqual(ordered.map(\.name), ["web"])
    }

    func testDependsOnCycleTerminatesAndIncludesAllServices() {
        let a = ComposeService(name: "a", dependsOn: ["b"])
        let b = ComposeService(name: "b", dependsOn: ["a"])
        let ordered = ComposeParser.topologicalOrder([a, b])
        XCTAssertEqual(Set(ordered.map(\.name)), Set(["a", "b"]))
        XCTAssertEqual(ordered.count, 2)
    }

    // MARK: - Unsupported directive detection

    func testUnsupportedPerServiceDirectivesAreIgnoredNotFatal() {
        let yaml = """
        services:
          web:
            image: nginx
            healthcheck:
              test: ["CMD", "curl", "-f", "http://localhost"]
            restart: always
            profiles:
              - debug
            deploy:
              replicas: 3
        """
        let parsed = ComposeParser.parse(yaml)
        XCTAssertEqual(parsed?.services.count, 1)
        let messages = parsed?.ignoredDirectives.joined(separator: "\n") ?? ""
        XCTAssertTrue(messages.contains("healthcheck"))
        XCTAssertTrue(messages.contains("restart"))
        XCTAssertTrue(messages.contains("profiles"))
        XCTAssertTrue(messages.contains("deploy"))
    }

    func testTopLevelUnsupportedDirectivesAreIgnoredNotFatal() {
        let yaml = """
        services:
          web:
            image: nginx
        networks:
          custom:
            driver: bridge
        volumes:
          data: {}
        secrets:
          token:
            file: ./token.txt
        """
        let parsed = ComposeParser.parse(yaml)
        XCTAssertEqual(parsed?.services.count, 1)
        let messages = parsed?.ignoredDirectives.joined(separator: "\n") ?? ""
        XCTAssertTrue(messages.contains("networks"))
        XCTAssertTrue(messages.contains("volumes"))
        XCTAssertTrue(messages.contains("secrets"))
    }

    func testTopLevelVersionAndExtensionFieldsAreNotWarned() {
        let yaml = """
        version: "3.8"
        x-common: &common
          restart: always
        services:
          web:
            image: nginx
        """
        let parsed = ComposeParser.parse(yaml)
        XCTAssertEqual(parsed?.ignoredDirectives, [])
    }

    func testServiceWithoutImageIsFlaggedAsSkipped() {
        let yaml = """
        services:
          web:
            build: .
        """
        let parsed = ComposeParser.parse(yaml)
        XCTAssertEqual(parsed?.services.first?.image, nil)
        let messages = parsed?.ignoredDirectives.joined(separator: "\n") ?? ""
        XCTAssertTrue(messages.contains("no 'image'"))
        XCTAssertTrue(messages.contains("build"))
    }

    // MARK: - Malformed input

    func testMalformedEmptyInputReturnsNil() {
        XCTAssertNil(ComposeParser.parse(""))
        XCTAssertNil(ComposeParser.parse("   \n  \n"))
    }

    func testMalformedNoServicesKeyReturnsNil() {
        let yaml = """
        version: "3.8"
        networks:
          default: {}
        """
        XCTAssertNil(ComposeParser.parse(yaml))
    }

    func testMalformedRandomTextReturnsNil() {
        XCTAssertNil(ComposeParser.parse("this is not a compose file at all"))
    }

    func testMalformedServicesAsScalarReturnsNil() {
        let yaml = """
        services: not-a-map
        """
        XCTAssertNil(ComposeParser.parse(yaml))
    }

    // MARK: - Comments

    func testCommentsAreStripped() {
        let yaml = """
        services:
          web: # the web tier
            image: nginx # pinned base
            ports:
              - "8080:80" # http
        """
        let parsed = ComposeParser.parse(yaml)
        XCTAssertEqual(parsed?.services.first?.image, "nginx")
        XCTAssertEqual(parsed?.services.first?.ports, ["8080:80"])
    }

    // MARK: - Project name sanitization

    func testSanitizedProjectNameLowercasesAndReplacesInvalidCharacters() {
        XCTAssertEqual(ComposeParser.sanitizedProjectName("My Cool App"), "my-cool-app")
        XCTAssertEqual(ComposeParser.sanitizedProjectName("Already-Fine_123"), "already-fine_123")
    }

    func testSanitizedProjectNameCollapsesDuplicateAndEdgeDashes() {
        XCTAssertEqual(ComposeParser.sanitizedProjectName("--weird//name--"), "weird-name")
    }

    func testSanitizedProjectNameFallsBackWhenEmpty() {
        XCTAssertEqual(ComposeParser.sanitizedProjectName(""), "compose-project")
        XCTAssertEqual(ComposeParser.sanitizedProjectName("###"), "compose-project")
    }

    func testNetworkNameDerivesFromProject() {
        XCTAssertEqual(ComposeParser.networkName(forProject: "demo"), "demo-net")
    }

    // MARK: - Full multi-service fixture

    func testFullFixtureWithAllSupportedDirectives() {
        let yaml = """
        version: "3.8"
        services:
          db:
            image: postgres:16
            environment:
              - POSTGRES_PASSWORD=secret
            volumes:
              - dbdata:/var/lib/postgresql/data
          web:
            image: myapp:latest
            container_name: myapp-web
            ports:
              - "3000:3000"
            environment:
              NODE_ENV: production
            command: node server.js
            depends_on:
              - db
        """
        let parsed = ComposeParser.parse(yaml)!
        XCTAssertEqual(parsed.services.count, 2)
        let ordered = ComposeParser.topologicalOrder(parsed.services)
        XCTAssertEqual(ordered.map(\.name), ["db", "web"])
        let web = parsed.services.first { $0.name == "web" }
        XCTAssertEqual(web?.resolvedContainerName(project: "demo"), "myapp-web")
        XCTAssertEqual(web?.command, ["node", "server.js"])
        XCTAssertEqual(web?.environment, ["NODE_ENV=production"])
    }
}
