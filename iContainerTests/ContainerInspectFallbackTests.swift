import XCTest
@testable import iContainer

/// `parseContainerInspect` against real `container inspect` output from
/// CLI 1.4.1: a stopped container (postgres) and a running one
/// (elasticsearch, with a populated status subtree).
final class ContainerInspectFallbackTests: XCTestCase {

    static let postgresStopped = #"""
[
  {
    "configuration" : {
      "capAdd" : [

      ],
      "capDrop" : [

      ],
      "creationDate" : "2026-06-15T20:37:28Z",
      "dns" : {
        "nameservers" : [

        ],
        "options" : [

        ],
        "searchDomains" : [

        ]
      },
      "id" : "postgres",
      "image" : {
        "descriptor" : {
          "digest" : "sha256:29ee7bb30d804447dc9a91fd0d74322ae1dc3a4072cc6346f70a5ed6e783b565",
          "mediaType" : "application/vnd.oci.image.index.v1+json",
          "size" : 10229
        },
        "reference" : "docker.io/library/postgres:latest"
      },
      "initProcess" : {
        "arguments" : [
          "postgres"
        ],
        "environment" : [
          "GOSU_VERSION=1.19",
          "POSTGRES_PASSWORD=secret",
          "PG_MAJOR=18",
          "PGDATA=/var/lib/postgresql/18/docker",
          "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/postgresql/18/bin",
          "LANG=en_US.utf8",
          "PG_VERSION=18.4-1.pgdg13+1"
        ],
        "executable" : "docker-entrypoint.sh",
        "rlimits" : [

        ],
        "supplementalGroups" : [

        ],
        "terminal" : false,
        "user" : {
          "id" : {
            "gid" : 0,
            "uid" : 0
          }
        },
        "workingDirectory" : "/"
      },
      "labels" : {

      },
      "mounts" : [

      ],
      "networks" : [
        {
          "network" : "default",
          "options" : {
            "hostname" : "postgres",
            "mtu" : 1280
          }
        }
      ],
      "platform" : {
        "architecture" : "arm64",
        "os" : "linux"
      },
      "publishedPorts" : [
        {
          "containerPort" : 5432,
          "count" : 1,
          "hostAddress" : "0.0.0.0",
          "hostPort" : 5432,
          "proto" : "tcp"
        }
      ],
      "publishedSockets" : [

      ],
      "readOnly" : false,
      "resources" : {
        "cpuOverhead" : 1,
        "cpus" : 2,
        "memoryInBytes" : 1073741824
      },
      "rosetta" : false,
      "runtimeHandler" : "container-runtime-linux",
      "ssh" : false,
      "stopSignal" : "SIGINT",
      "sysctls" : {

      },
      "useInit" : false,
      "virtualization" : false
    },
    "id" : "postgres",
    "status" : {
      "networks" : [

      ],
      "state" : "stopped"
    }
  }
]
"""#

    static let elasticsearchRunning = #"""
[
  {
    "configuration" : {
      "capAdd" : [

      ],
      "capDrop" : [

      ],
      "creationDate" : "2026-06-15T20:38:43Z",
      "dns" : {
        "nameservers" : [

        ],
        "options" : [

        ],
        "searchDomains" : [

        ]
      },
      "id" : "elasticsearch",
      "image" : {
        "descriptor" : {
          "digest" : "sha256:84a73ced8390c059e7bc2858595c68dc36e6f8bdb98895dcab0074eda35ac96e",
          "mediaType" : "application/vnd.docker.distribution.manifest.list.v2+json",
          "size" : 685
        },
        "reference" : "docker.elastic.co/elasticsearch/elasticsearch:8.15.0"
      },
      "initProcess" : {
        "arguments" : [
          "--",
          "/usr/local/bin/docker-entrypoint.sh",
          "eswrapper"
        ],
        "environment" : [
          "ELASTIC_CONTAINER=true",
          "PATH=/usr/share/elasticsearch/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        ],
        "executable" : "/bin/tini",
        "rlimits" : [

        ],
        "supplementalGroups" : [

        ],
        "terminal" : false,
        "user" : {
          "raw" : {
            "userString" : "1000:0"
          }
        },
        "workingDirectory" : "/usr/share/elasticsearch"
      },
      "labels" : {

      },
      "mounts" : [

      ],
      "networks" : [
        {
          "network" : "default",
          "options" : {
            "hostname" : "elasticsearch",
            "mtu" : 1280
          }
        }
      ],
      "platform" : {
        "architecture" : "arm64",
        "os" : "linux"
      },
      "publishedPorts" : [
        {
          "containerPort" : 9200,
          "count" : 1,
          "hostAddress" : "0.0.0.0",
          "hostPort" : 9200,
          "proto" : "tcp"
        }
      ],
      "publishedSockets" : [

      ],
      "readOnly" : false,
      "resources" : {
        "cpuOverhead" : 1,
        "cpus" : 4,
        "memoryInBytes" : 2147483648
      },
      "rosetta" : false,
      "runtimeHandler" : "container-runtime-linux",
      "ssh" : false,
      "sysctls" : {

      },
      "useInit" : false,
      "virtualization" : false
    },
    "id" : "elasticsearch",
    "status" : {
      "networks" : [
        {
          "hostname" : "elasticsearch",
          "ipv4Address" : "192.168.65.6/24",
          "ipv4Gateway" : "192.168.65.1",
          "ipv6Address" : "fd26:7379:c7a:dc84:f81d:39ff:feee:2c50/64",
          "macAddress" : "fa:1d:39:ee:2c:50",
          "mtu" : 1280,
          "network" : "default",
          "variant" : "reserved"
        }
      ],
      "startedDate" : "2026-09-18T21:27:35Z",
      "state" : "running"
    }
  }
]
"""#

    func testStoppedContainerFields() throws {
        let fb = try XCTUnwrap(parseContainerInspect(Self.postgresStopped))
        XCTAssertEqual(fb.id, "postgres")
        XCTAssertEqual(fb.status, "stopped")
        XCTAssertEqual(fb.image, "docker.io/library/postgres:latest")
        XCTAssertEqual(fb.imageDigest?.hasPrefix("sha256:"), true)
        XCTAssertEqual(fb.created, "2026-06-15T20:37:28Z", "CLI ≥ 1.x uses configuration.creationDate")
        XCTAssertNil(fb.startedDate)
        XCTAssertEqual(fb.command, "docker-entrypoint.sh postgres")
        XCTAssertEqual(fb.user, "0:0")
        XCTAssertEqual(fb.workingDir, "/")
        XCTAssertEqual(fb.platform, "linux/arm64")
        XCTAssertEqual(fb.runtimeHandler, "container-runtime-linux")
        XCTAssertEqual(fb.stopSignal, "SIGINT")
        XCTAssertEqual(fb.rosetta, false)
        XCTAssertEqual(fb.useInit, false)
        XCTAssertEqual(fb.virtualization, false)
        XCTAssertEqual(fb.resources?.cpus, 2)
        XCTAssertEqual(fb.resources?.memoryBytes, 1_073_741_824)
        XCTAssertEqual(fb.ports, ["0.0.0.0:5432->5432/tcp"])
        XCTAssertEqual(fb.networkName, "default")
        XCTAssertEqual(fb.mtu, 1280)
        XCTAssertEqual(fb.hostname, "postgres")
        XCTAssertTrue(fb.labels.isEmpty)
        XCTAssertTrue(fb.capabilitiesAdded.isEmpty)
        XCTAssertTrue(fb.mounts.isEmpty)
    }

    func testRunningContainerStatusFields() throws {
        let fb = try XCTUnwrap(parseContainerInspect(Self.elasticsearchRunning))
        XCTAssertEqual(fb.status, "running")
        XCTAssertEqual(fb.startedDate, "2026-09-18T21:27:35Z")
        XCTAssertEqual(fb.ipv4Address, "192.168.65.6/24")
        XCTAssertEqual(fb.ipv4Gateway, "192.168.65.1")
        XCTAssertEqual(fb.macAddress, "fa:1d:39:ee:2c:50")
        XCTAssertEqual(fb.networkName, "default")
        XCTAssertEqual(fb.user, "1000:0", "raw userString form")
    }

    func testMountKindsAndVolumeName() throws {
        let json = """
        [{"id": "x", "status": {"state": "stopped", "networks": []}, "configuration": {"id": "x", "mounts": [
            {"type": {"volume": {"name": "pgdata", "format": "ext4"}}, "source": "/x/volume.img", "destination": "/var/lib/postgresql/data"},
            {"type": {"virtiofs": {}}, "source": "/Users/demo/cfg", "destination": "/etc/cfg"},
            {"type": {"tmpfs": {}}, "source": "", "destination": "/run"}
        ]}}]
        """
        let fb = try XCTUnwrap(parseContainerInspect(json))
        XCTAssertEqual(fb.mounts.count, 3)
        XCTAssertEqual(fb.mounts[0].kind, "volume")
        XCTAssertEqual(fb.mounts[0].volumeName, "pgdata")
        XCTAssertEqual(fb.mounts[1].kind, "virtiofs")
        XCTAssertNil(fb.mounts[1].volumeName)
        XCTAssertEqual(fb.mounts[2].kind, "tmpfs")
        XCTAssertEqual(fb.mounts[2].source, "")
    }

    func testLabelsCapabilitiesAndSysctls() throws {
        let json = """
        [{"id": "x", "status": "running", "configuration": {"id": "x",
            "labels": {"com.icontainer.compose.project": "demo"},
            "capAdd": ["NET_ADMIN"], "capDrop": ["ALL"],
            "sysctls": {"net.ipv4.ip_forward": "1"},
            "useInit": true, "virtualization": true,
            "initProcess": {"user": {"id": {"uid": 472}}}
        }}]
        """
        let fb = try XCTUnwrap(parseContainerInspect(json))
        XCTAssertEqual(fb.labels, ["com.icontainer.compose.project": "demo"])
        XCTAssertEqual(fb.capabilitiesAdded, ["NET_ADMIN"])
        XCTAssertEqual(fb.capabilitiesDropped, ["ALL"])
        XCTAssertEqual(fb.sysctls, ["net.ipv4.ip_forward": "1"])
        XCTAssertEqual(fb.useInit, true)
        XCTAssertEqual(fb.virtualization, true)
        XCTAssertEqual(fb.user, "472", "uid without gid")
        XCTAssertEqual(fb.status, "running", "legacy string status still accepted")
    }

    func testDateHelpers() {
        XCTAssertEqual(ContainerInfoView.formatDate("not a date"), "not a date")
        XCTAssertNotNil(ContainerInfoView.parseDate("2026-09-18T21:27:35Z"))
        let now = ContainerInfoView.parseDate("2026-09-18T23:41:35Z")!
        XCTAssertEqual(ContainerInfoView.uptimeSuffix("2026-09-18T21:27:35Z", now: now), " · up 2h 14m")
        XCTAssertEqual(ContainerInfoView.uptimeSuffix("2026-09-16T21:27:35Z", now: now), " · up 2d 2h")
        XCTAssertEqual(ContainerInfoView.uptimeSuffix("garbage", now: now), "")
    }
}
