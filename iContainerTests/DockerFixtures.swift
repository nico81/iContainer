import Foundation

/// Real `docker` CLI output captured on 2026-09-07 (Docker 29.4.3 / Docker Desktop 4.73,
/// containerd image store) with personal paths sanitised. Kept as literals so the
/// tests need no bundle plumbing.
enum DockerFixtures {
    static let imagesNDJSON = #"""
{"Containers":"0","CreatedAt":"2026-04-15 22:01:25 +0200 CEST","CreatedSince":"4 months ago","Digest":"\u003cnone\u003e","ID":"5b10f432ef3d","Repository":"alpine","SharedSize":"N/A","Size":"13.6MB","Tag":"latest","UniqueSize":"N/A"}
{"Containers":"0","CreatedAt":"2026-04-15 22:01:25 +0200 CEST","CreatedSince":"4 months ago","Digest":"\u003cnone\u003e","ID":"5b10f432ef3d","Repository":"demo/private-test","SharedSize":"N/A","Size":"13.6MB","Tag":"latest","UniqueSize":"N/A"}
{"Containers":"1","CreatedAt":"2026-03-27 14:34:03 +0100 CET","CreatedSince":"5 months ago","Digest":"\u003cnone\u003e","ID":"3aa7be574942","Repository":"victoriametrics/vmagent","SharedSize":"N/A","Size":"44.7MB","Tag":"latest","UniqueSize":"N/A"}
{"Containers":"1","CreatedAt":"2026-03-27 14:33:11 +0100 CET","CreatedSince":"5 months ago","Digest":"\u003cnone\u003e","ID":"67c689e15218","Repository":"victoriametrics/victoria-metrics","SharedSize":"N/A","Size":"51.7MB","Tag":"latest","UniqueSize":"N/A"}
{"Containers":"1","CreatedAt":"2026-03-25 09:25:50 +0100 CET","CreatedSince":"5 months ago","Digest":"\u003cnone\u003e","ID":"83749231c383","Repository":"grafana/grafana","SharedSize":"N/A","Size":"950MB","Tag":"latest","UniqueSize":"N/A"}
{"Containers":"0","CreatedAt":"2026-02-01 06:22:40 +0100 CET","CreatedSince":"7 months ago","Digest":"\u003cnone\u003e","ID":"d453f54c8332","Repository":"alpine/git","SharedSize":"N/A","Size":"145MB","Tag":"latest","UniqueSize":"N/A"}
{"Containers":"1","CreatedAt":"2026-01-06 15:53:56 +0100 CET","CreatedSince":"8 months ago","Digest":"\u003cnone\u003e","ID":"e5fd5e8b43ac","Repository":"prom/snmp-exporter","SharedSize":"N/A","Size":"33.9MB","Tag":"latest","UniqueSize":"N/A"}
{"Containers":"1","CreatedAt":"2025-10-25 22:11:08 +0200 CEST","CreatedSince":"10 months ago","Digest":"\u003cnone\u003e","ID":"3ac34ce007ac","Repository":"prom/node-exporter","SharedSize":"N/A","Size":"39.5MB","Tag":"latest","UniqueSize":"N/A"}
"""#

    static let psNDJSON = #"""
{"Command":"\"/run.sh\"","CreatedAt":"2026-04-06 00:19:31 +0200 CEST","ID":"2cb3aced0180","Image":"grafana/grafana","Labels":"desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/3000/tcp=:3000,maintainer=Grafana Labs \u003chello@grafana.com\u003e,org.opencontainers.image.source=https://github.com/grafana/grafana","LocalVolumes":"0","Mounts":"","Names":"grafana","Networks":"vm-net","Platform":{"architecture":"arm64","os":"linux"},"Ports":"","RunningFor":"5 months ago","Size":"0B","State":"exited","Status":"Exited (0) 4 months ago"}
{"Command":"\"/bin/snmp_exporter …\"","CreatedAt":"2026-04-05 23:20:14 +0200 CEST","ID":"3d266e00e2af","Image":"prom/snmp-exporter","Labels":"desktop.docker.io/binds/0/Source=/Users/demo/docker-data/snmp-exporter/snmp.yml,desktop.docker.io/binds/0/SourceKind=hostFile,desktop.docker.io/binds/0/Target=/etc/snmp_exporter/snmp.yml,desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/9116/tcp=:9116,maintainer=The Prometheus Authors \u003cprometheus-developers@googlegroups.com\u003e","LocalVolumes":"0","Mounts":"/host_mnt/User…","Names":"snmp-exporter","Networks":"vm-net","Platform":{"architecture":"arm64","os":"linux"},"Ports":"","RunningFor":"5 months ago","Size":"0B","State":"exited","Status":"Exited (2) 4 months ago"}
{"Command":"\"/bin/node_exporter …\"","CreatedAt":"2026-04-05 22:57:13 +0200 CEST","ID":"f0993c16ca2e","Image":"prom/node-exporter","Labels":"desktop.docker.io/binds/0/Source=/Users/demo/docker-data/node-exporter/textfile,desktop.docker.io/binds/0/SourceKind=hostFile,desktop.docker.io/binds/0/Target=/textfile,desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/9100/tcp=:9100,maintainer=The Prometheus Authors \u003cprometheus-developers@googlegroups.com\u003e","LocalVolumes":"0","Mounts":"/host_mnt/User…","Names":"node-exporter","Networks":"vm-net","Platform":{"architecture":"arm64","os":"linux"},"Ports":"","RunningFor":"5 months ago","Size":"0B","State":"exited","Status":"Exited (2) 4 months ago"}
{"Command":"\"/vmagent-prod -prom…\"","CreatedAt":"2026-04-05 22:56:51 +0200 CEST","ID":"341ab5206894","Image":"victoriametrics/vmagent","Labels":"desktop.docker.io/binds/0/Source=/Users/demo/docker-data/vmagent/prometheus.yml,desktop.docker.io/binds/0/SourceKind=hostFile,desktop.docker.io/binds/0/Target=/etc/prometheus/prometheus.yml,desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/8429/tcp=:8429,org.opencontainers.image.created=2026-03-27T13:33:58Z,org.opencontainers.image.documentation=https://docs.victoriametrics.com/,org.opencontainers.image.source=https://github.com/VictoriaMetrics/VictoriaMetrics,org.opencontainers.image.title=vmagent,org.opencontainers.image.vendor=VictoriaMetrics,org.opencontainers.image.version=v1.139.0","LocalVolumes":"0","Mounts":"/host_mnt/User…","Names":"vmagent","Networks":"vm-net","Platform":{"architecture":"arm64","os":"linux"},"Ports":"","RunningFor":"5 months ago","Size":"0B","State":"exited","Status":"Exited (0) 4 months ago"}
{"Command":"\"/victoria-metrics-p…\"","CreatedAt":"2026-04-05 22:56:14 +0200 CEST","ID":"ce8349bb8bce","Image":"victoriametrics/victoria-metrics:latest","Labels":"desktop.docker.io/binds/0/Source=/Users/demo/docker-data/vmdata,desktop.docker.io/binds/0/SourceKind=hostFile,desktop.docker.io/binds/0/Target=/victoria-metrics-data,desktop.docker.io/ports.scheme=v2,desktop.docker.io/ports/8428/tcp=:8428,org.opencontainers.image.created=2026-03-27T13:33:05Z,org.opencontainers.image.documentation=https://docs.victoriametrics.com/,org.opencontainers.image.source=https://github.com/VictoriaMetrics/VictoriaMetrics,org.opencontainers.image.title=victoria-metrics,org.opencontainers.image.vendor=VictoriaMetrics,org.opencontainers.image.version=v1.139.0","LocalVolumes":"0","Mounts":"/host_mnt/User…","Names":"victoriametrics","Networks":"vm-net","Platform":{"architecture":"arm64","os":"linux"},"Ports":"","RunningFor":"5 months ago","Size":"0B","State":"exited","Status":"Exited (2) 3 months ago"}
"""#

    static let inspectGrafana = #"""
{
  "Id": "2cb3aced0180c53efa40035e8f5401081d17998ef9c7f44561e2bda8bdb04d41",
  "Name": "/grafana",
  "Image": "sha256:83749231c3835e390a3144e5e940203e42b9589761f20ef3169c716e734ad505",
  "Platform": "linux",
  "State": {
    "Status": "exited",
    "Running": false
  },
  "Config": {
    "User": "472",
    "ExposedPorts": {
      "3000/tcp": {}
    },
    "Env": [
      "PATH=/usr/share/grafana/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      "GF_PATHS_CONFIG=/etc/grafana/grafana.ini",
      "GF_PATHS_DATA=/var/lib/grafana",
      "GF_PATHS_HOME=/usr/share/grafana",
      "GF_PATHS_LOGS=/var/log/grafana",
      "GF_PATHS_PLUGINS=/var/lib/grafana/plugins",
      "GF_PATHS_PROVISIONING=/etc/grafana/provisioning"
    ],
    "Cmd": null,
    "Image": "grafana/grafana",
    "WorkingDir": "/usr/share/grafana",
    "Entrypoint": [
      "/run.sh"
    ],
    "Labels": {
      "maintainer": "Grafana Labs <hello@grafana.com>",
      "org.opencontainers.image.source": "https://github.com/grafana/grafana"
    },
    "Healthcheck": null
  },
  "HostConfig": {
    "Binds": null,
    "PortBindings": {
      "3000/tcp": [
        {
          "HostIp": "",
          "HostPort": "3000"
        }
      ]
    },
    "RestartPolicy": {
      "Name": "no",
      "MaximumRetryCount": 0
    },
    "NetworkMode": "vm-net",
    "Memory": 0,
    "NanoCpus": 0,
    "CapAdd": null,
    "CapDrop": null,
    "Privileged": false,
    "ReadonlyRootfs": false,
    "Tmpfs": null,
    "Devices": [],
    "ExtraHosts": null,
    "Links": null,
    "DeviceRequests": null
  },
  "Mounts": [],
  "NetworkSettings": {
    "Networks": {
      "vm-net": {}
    }
  }
}
"""#

    static let inspectSnmpExporter = #"""
{
  "Id": "3d266e00e2afcf8bf7fd9d5436b1a3f8fac9af0011549bce69925de2ef44e291",
  "Name": "/snmp-exporter",
  "Image": "sha256:e5fd5e8b43ace6c088fe9bf0b37b7fff0e04380bee352be7ec41b853a4dd5859",
  "Platform": "linux",
  "State": {
    "Status": "exited",
    "Running": false
  },
  "Config": {
    "User": "",
    "ExposedPorts": {
      "9116/tcp": {}
    },
    "Env": [
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    ],
    "Cmd": [
      "--config.file=/etc/snmp_exporter/snmp.yml"
    ],
    "Image": "prom/snmp-exporter",
    "WorkingDir": "",
    "Entrypoint": [
      "/bin/snmp_exporter"
    ],
    "Labels": {
      "maintainer": "The Prometheus Authors <prometheus-developers@googlegroups.com>"
    },
    "Healthcheck": null
  },
  "HostConfig": {
    "Binds": [
      "/Users/demo/docker-data/snmp-exporter/snmp.yml:/etc/snmp_exporter/snmp.yml"
    ],
    "PortBindings": {
      "9116/tcp": [
        {
          "HostIp": "",
          "HostPort": "9116"
        }
      ]
    },
    "RestartPolicy": {
      "Name": "no",
      "MaximumRetryCount": 0
    },
    "NetworkMode": "vm-net",
    "Memory": 0,
    "NanoCpus": 0,
    "CapAdd": null,
    "CapDrop": null,
    "Privileged": false,
    "ReadonlyRootfs": false,
    "Tmpfs": null,
    "Devices": [],
    "ExtraHosts": null,
    "Links": null,
    "DeviceRequests": null
  },
  "Mounts": [
    {
      "Type": "bind",
      "Source": "/Users/demo/docker-data/snmp-exporter/snmp.yml",
      "Destination": "/etc/snmp_exporter/snmp.yml",
      "Mode": "",
      "RW": true,
      "Propagation": "rprivate"
    }
  ],
  "NetworkSettings": {
    "Networks": {
      "vm-net": {}
    }
  }
}
"""#

    /// `container image load -i` output for the alpine probe.
    static let loadOutput = #"""
docker.io/library/alpine:latest
untagged@sha256:175cdb0651aaf8b1fe584a0076312b70def5ba29c5750134cacf99396acd89c1
"""#
}
