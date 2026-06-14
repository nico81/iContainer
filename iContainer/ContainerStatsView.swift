import SwiftUI
import Charts

/// "Stats" tab of the container detail view.
///
/// Renders the latest sample as numeric rows plus three time-series charts
/// (CPU %, memory MB, network KB/s). The series come from `statsStore`,
/// which is fed in the background for every running container, so the chart
/// is already populated when the tab opens even if the container has been
/// running for a while. While the tab is visible it also samples its own
/// container directly (`sampleStats(for:)`) so the chart stays live at its
/// own cadence. The charts use a fixed five-minute window anchored to the
/// newest sample (Activity Monitor-style), so new data enters from the
/// right edge and scrolls left.

struct ContainerStatsView: View {
    let details: ContainerDetails?
    let containerId: String
    let cpuLimit: Int?
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var statsStore: ContainerStatsStore
    @State private var refreshTask: Task<Void, Never>?
    @State private var didAttemptSample = false

    private let refreshIntervalNanos: UInt64 = 3_000_000_000
    private let chartWindowSeconds: TimeInterval = 300

    /// History is owned by `ContainerStatsStore` and fed in the background
    /// for every running container, so opening this tab shows whatever was
    /// already collected rather than starting from an empty chart.
    private var history: ContainerStatsStore.History? { statsStore.history(for: containerId) }
    private var stats: ContainerStats? { history?.latest }
    private var cpuSeries: [StatPoint] { history?.cpuSeries ?? [] }
    private var memorySeries: [StatPoint] { history?.memorySeries ?? [] }
    private var netSeries: [StatPoint] { history?.netSeries ?? [] }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 24
            let sectionInnerPadding: CGFloat = 32
            let sectionContentWidth = max(0, proxy.size.width - (horizontalPadding * 2) - sectionInnerPadding)
            let statsHeight = max(420, proxy.size.height - 180)
            let chartHeight = max(90, (statsHeight - 48) / 3)
            let infoBoxHeight = max(150, chartHeight)
            ScrollView {
                if let details = details {
                    VStack(alignment: .leading, spacing: 24) {
                        ContainerHeaderView(details: details)
                        DetailSection(title: "Resource Stats", icon: "speedometer") {
                            if let stats = stats {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        DetailRow(label: "CPU %", value: normalizedCpuPercentText(for: stats))
                                        DetailRow(label: "Memory Usage", value: stats.memoryUsage)
                                        DetailRow(label: "Net Rx/Tx", value: stats.netRxTx)
                                        DetailRow(label: "Block I/O", value: stats.blockIo)
                                        DetailRow(label: "Pids", value: stats.pids)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 18)
                                    .frame(width: sectionContentWidth * 0.33, alignment: .topLeading)
                                    .frame(minHeight: infoBoxHeight, alignment: .topLeading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(AppRadius.card)
                                    .cardOutline(AppRadius.card)

                                    VStack(alignment: .leading, spacing: 12) {
                                        ChartPanel(title: "CPU %") {
                                            StatTimelineChart(
                                                points: cpuSeries.map {
                                                    StatPoint(time: $0.time, value: normalizedCpuPercentValue(raw: $0.value))
                                                },
                                                domain: chartDomain,
                                                yDomain: 0...100
                                            )
                                        }
                                        .frame(height: infoBoxHeight)

                                        ChartPanel(title: "Memory (MB)") {
                                            StatTimelineChart(points: memorySeries, domain: chartDomain)
                                        }
                                        .frame(height: chartHeight)

                                        ChartPanel(title: "Network (KB/s)") {
                                            StatTimelineChart(points: netSeries, domain: chartDomain)
                                        }
                                        .frame(height: chartHeight)
                                    }
                                    .padding()
                                    .padding(.top, -16)
                                    .padding(.trailing, 4)
                                    .frame(width: sectionContentWidth * 0.67, alignment: .leading)
                                }
                                .padding(.top, -8)
                                .frame(width: sectionContentWidth, alignment: .leading)
                                .frame(height: statsHeight)
                            } else if !didAttemptSample {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.1)
                                    Text("Loading")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 80)
                            } else {
                                Text("No stats available.")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 16)
                } else {
                    ProgressView("Loading Details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 50)
                }
            }
        }
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    private func normalizedCpuPercentText(for stats: ContainerStats) -> String {
        guard let normalized = normalizedCpuPercentValue(for: stats) else { return stats.cpuPercent }
        return String(format: "%.2f%%", normalized)
    }

    private func normalizedCpuPercentValue(for stats: ContainerStats) -> Double? {
        let rawValue = stats.cpuPercentValue ?? parsePercent(stats.cpuPercent)
        guard let cpu = rawValue else { return nil }
        let coreCount = effectiveCoreCount(for: cpu)
        return min(100, cpu / coreCount)
    }

    private func normalizedCpuPercentValue(raw cpuValue: Double) -> Double {
        let coreCount = effectiveCoreCount(for: cpuValue)
        return min(100, cpuValue / coreCount)
    }

    private func effectiveCoreCount(for cpuValue: Double) -> Double {
        if let cpuLimit, cpuLimit > 0 {
            return Double(cpuLimit)
        }
        if cpuValue > 100 {
            return Double(Int(ceil(cpuValue / 100.0)))
        }
        return 1
    }

    /// Keeps this container's chart live while the tab is open by sampling
    /// it directly. The background poll already samples every running
    /// container, but this guarantees fresh data at the tab's own cadence
    /// (and works even when global polling is set to "manual").
    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                await containerManager.sampleStats(for: containerId)
                didAttemptSample = true
                try? await Task.sleep(nanoseconds: refreshIntervalNanos)
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Fixed five-minute window anchored to the newest sample, Activity
    /// Monitor-style: the span never stretches to fit the data, so fresh
    /// samples enter at the right edge and scroll left as time passes.
    private var chartDomain: ClosedRange<Date> {
        let end = [
            cpuSeries.last?.time,
            memorySeries.last?.time,
            netSeries.last?.time
        ].compactMap { $0 }.max() ?? Date()
        return end.addingTimeInterval(-chartWindowSeconds)...end
    }
}

// MARK: - Timeline chart

/// Line + soft area chart over a fixed time window. Consecutive samples
/// further apart than `gapThreshold` (e.g. after leaving and re-entering
/// the tab) are split into separate line segments instead of being joined
/// by a misleading straight line; a segment with a single sample is drawn
/// as a dot so the very first poll is visible immediately.
struct StatTimelineChart: View {
    let points: [StatPoint]
    let domain: ClosedRange<Date>
    var yDomain: ClosedRange<Double>? = nil

    /// Maximum spacing between consecutive samples before the chart breaks
    /// them into separate segments (drawn as isolated dots instead of a
    /// connected line). Restart gaps don't need to be detected here —
    /// stopping a container clears its history in `ContainerStatsStore`
    /// outright, so a "restart" never appears as a gap within a series.
    /// The threshold only needs to be generous enough to bridge a slow
    /// global poll cycle (configurable, can be 60+ s).
    var gapThreshold: TimeInterval = 120

    private struct SegmentPoint: Identifiable {
        let id: UUID
        let segment: Int
        let time: Date
        let value: Double
        var isIsolated: Bool
    }

    private var segmentedPoints: [SegmentPoint] {
        var result: [SegmentPoint] = []
        var segment = 0
        var segmentSize = 0
        for point in points {
            if let last = result.last {
                if point.time.timeIntervalSince(last.time) > gapThreshold {
                    segment += 1
                    segmentSize = 0
                }
            }
            segmentSize += 1
            result.append(SegmentPoint(
                id: point.id,
                segment: segment,
                time: point.time,
                value: point.value,
                isIsolated: segmentSize == 1
            ))
            if segmentSize == 2 {
                // The previous point is no longer alone in its segment.
                result[result.count - 2].isIsolated = false
            }
        }
        return result
    }

    var body: some View {
        let chart = Chart(segmentedPoints) { point in
            if point.isIsolated {
                PointMark(
                    x: .value("Time", point.time),
                    y: .value("Value", point.value)
                )
                .symbolSize(20)
                .foregroundStyle(Color.accentColor)
            } else {
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Value", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Value", point.value),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(Color.accentColor)
            }
        }
        .chartXScale(domain: domain)
        .chartLegend(.hidden)

        if let yDomain {
            chart.chartYScale(domain: yDomain)
        } else {
            chart
        }
    }
}

// MARK: - Chart chrome

/// Boxed wrapper that gives each `Chart` a title and a subtle outline so
/// the three series visually line up. Generic over the chart content so
/// each panel can pass its own `Chart { LineMark(...) }` block.
struct ChartPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .cornerRadius(AppRadius.small)
        .cardOutline(AppRadius.small)
    }
}

// MARK: - Model

struct ContainerStats: Equatable {
    let cpuPercent: String
    let memoryUsage: String
    let pids: String
    let netRxTx: String
    let blockIo: String
    let cpuPercentValue: Double?
    let memoryUsageBytes: Int64?
    let netRxBytes: Int64?
    let netTxBytes: Int64?
}

struct StatPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

/// Aggregate resource snapshot across every running container managed by
/// the `container` service (including infrastructure workers like the
/// BuildKit shim — those are real work the service is doing). Built from
/// the multi-row table that `container stats --no-stream` returns with no
/// arguments, which Apple itself exposes as the "all containers" view.
struct ServiceStats: Equatable {
    let runningContainerCount: Int
    /// Raw sum of per-container Cpu %. Can exceed 100 (each container is
    /// per-core), so the view normalizes against host core count for display.
    let cpuPercentValue: Double
    let memoryUsageBytes: Int64
    let memoryLimitBytes: Int64
    let netRxBytes: Int64
    let netTxBytes: Int64
    let blockReadBytes: Int64
    let blockWriteBytes: Int64
}

/// Parses the multi-row table output of `container stats --no-stream`
/// (no arguments), returning the aggregate sums. Returns nil if the table
/// has no data rows.
func parseServiceStats(_ output: String) -> ServiceStats? {
    let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard lines.count >= 2 else { return nil }
    let header = lines[0]
    let columnNames = ["Container ID", "Cpu %", "Memory Usage", "Net Rx/Tx", "Block I/O", "Pids"]
    let ranges = columnRanges(in: header, columns: columnNames)
    guard !ranges.isEmpty else { return nil }

    var count = 0
    var cpuSum: Double = 0
    var memUsage: Int64 = 0
    var memLimit: Int64 = 0
    var netRx: Int64 = 0
    var netTx: Int64 = 0
    var blkRead: Int64 = 0
    var blkWrite: Int64 = 0

    for line in lines.dropFirst() {
        var map: [String: String] = [:]
        for (name, range) in ranges {
            map[name.lowercased()] = substring(line, startOffset: range.start, endOffset: range.end)
                .trimmingCharacters(in: .whitespaces)
        }
        if let cpu = map["cpu %"].flatMap({ parsePercent($0) }) { cpuSum += cpu }
        if let pair = map["memory usage"].flatMap({ parseUsageAndLimit($0) }) {
            memUsage += pair.usage
            memLimit += pair.limit ?? 0
        }
        if let net = map["net rx/tx"].flatMap({ parseRxTx($0) }) {
            netRx += net.rx
            netTx += net.tx
        }
        if let blk = map["block i/o"].flatMap({ parseRxTx($0) }) {
            blkRead += blk.rx
            blkWrite += blk.tx
        }
        count += 1
    }
    guard count > 0 else { return nil }
    return ServiceStats(
        runningContainerCount: count,
        cpuPercentValue: cpuSum,
        memoryUsageBytes: memUsage,
        memoryLimitBytes: memLimit,
        netRxBytes: netRx,
        netTxBytes: netTx,
        blockReadBytes: blkRead,
        blockWriteBytes: blkWrite
    )
}

private struct ColumnRange {
    let start: Int
    let end: Int
}

// MARK: - Parsing

/// Parses the JSON-or-table output of `container stats`. Tries JSON first
/// (array or single object), falls back to the columnar text format.
func parseContainerStats(_ output: String) -> ContainerStats? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let data = trimmed.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data, options: []) {
        if let array = json as? [[String: Any]], let first = array.first {
            return statsFromDict(first)
        } else if let dict = json as? [String: Any] {
            return statsFromDict(dict)
        }
    }
    return statsFromTable(trimmed)
}

private func statsFromDict(_ dict: [String: Any]) -> ContainerStats? {
    let cpu = inspectStringIn(dict, keys: ["cpu", "cpuPercent", "cpu_percent", "cpuPct"]) ?? "-"
    let cpuValue = parsePercent(cpu)
    let memUsageBytes = inspectInt64In(dict, keys: ["memoryUsageBytes", "memUsageBytes"])
    let memLimitBytes = inspectInt64In(dict, keys: ["memoryLimitBytes", "memLimitBytes"])
    let memUsage = formatUsageAndLimit(usageBytes: memUsageBytes, limitBytes: memLimitBytes)
        ?? inspectStringIn(dict, keys: ["memUsage", "memoryUsage", "mem_usage", "memory"])
        ?? "-"
    let pids = inspectStringIn(dict, keys: ["pids", "numProcesses", "processes"]) ?? "-"
    let netRxBytes = inspectInt64In(dict, keys: ["networkRxBytes", "netRxBytes", "rxBytes"])
    let netTxBytes = inspectInt64In(dict, keys: ["networkTxBytes", "netTxBytes", "txBytes"])
    let netRxTx = formatRxTx(rxBytes: netRxBytes, txBytes: netTxBytes)
        ?? inspectStringIn(dict, keys: ["netRx", "networkRx", "rx", "net_rx"])
        ?? "-"
    let blkReadBytes = inspectInt64In(dict, keys: ["blockReadBytes", "blkReadBytes", "readBytes"])
    let blkWriteBytes = inspectInt64In(dict, keys: ["blockWriteBytes", "blkWriteBytes", "writeBytes"])
    let blockIo = formatRxTx(rxBytes: blkReadBytes, txBytes: blkWriteBytes)
        ?? inspectStringIn(dict, keys: ["blockRead", "blkRead", "block_read"])
        ?? "-"
    return ContainerStats(
        cpuPercent: cpu,
        memoryUsage: memUsage,
        pids: pids,
        netRxTx: netRxTx,
        blockIo: blockIo,
        cpuPercentValue: cpuValue,
        memoryUsageBytes: memUsageBytes,
        netRxBytes: netRxBytes,
        netTxBytes: netTxBytes
    )
}

private func statsFromTable(_ output: String) -> ContainerStats? {
    let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard lines.count >= 2 else { return nil }
    let header = lines[0]
    let valueLine = lines[1]
    let columnNames = ["Container ID", "Cpu %", "Memory Usage", "Net Rx/Tx", "Block I/O", "Pids"]
    let ranges = columnRanges(in: header, columns: columnNames)
    guard !ranges.isEmpty else { return nil }
    var map: [String: String] = [:]
    for (name, range) in ranges {
        let value = substring(valueLine, startOffset: range.start, endOffset: range.end)
            .trimmingCharacters(in: .whitespaces)
        map[name.lowercased()] = value
    }
    let cpu = map["cpu %"] ?? map["cpu%"] ?? "-"
    let cpuValue = parsePercent(cpu)
    let mem = map["memory usage"] ?? map["memusage"] ?? "-"
    let net = map["net rx/tx"] ?? map["netrx/tx"] ?? "-"
    let block = map["block i/o"] ?? map["block i/o"] ?? "-"
    let pids = map["pids"] ?? "-"
    let memBytes = parseUsageAndLimit(mem)?.usage
    let netBytes = parseRxTx(net)
    return ContainerStats(
        cpuPercent: cpu,
        memoryUsage: mem,
        pids: pids,
        netRxTx: net,
        blockIo: block,
        cpuPercentValue: cpuValue,
        memoryUsageBytes: memBytes,
        netRxBytes: netBytes?.rx,
        netTxBytes: netBytes?.tx
    )
}

private func columnRanges(in header: String, columns: [String]) -> [String: ColumnRange] {
    var starts: [(name: String, offset: Int)] = []
    for name in columns {
        if let range = header.range(of: name) {
            let offset = header.distance(from: header.startIndex, to: range.lowerBound)
            starts.append((name, offset))
        }
    }
    let sorted = starts.sorted { $0.offset < $1.offset }
    var result: [String: ColumnRange] = [:]
    for (idx, item) in sorted.enumerated() {
        let start = item.offset
        let end = (idx + 1 < sorted.count) ? sorted[idx + 1].offset : header.count
        result[item.name] = ColumnRange(start: start, end: end)
    }
    return result
}

private func substring(_ text: String, startOffset: Int, endOffset: Int) -> String {
    let safeStart = max(0, min(startOffset, text.count))
    let safeEnd = max(safeStart, min(endOffset, text.count))
    let startIndex = text.index(text.startIndex, offsetBy: safeStart)
    let endIndex = text.index(text.startIndex, offsetBy: safeEnd)
    return String(text[startIndex..<endIndex])
}

private func formatUsageAndLimit(usageBytes: Int64?, limitBytes: Int64?) -> String? {
    guard let usageBytes else { return nil }
    let usage = ByteCountFormatter.string(fromByteCount: usageBytes, countStyle: .memory)
    if let limitBytes {
        let limit = ByteCountFormatter.string(fromByteCount: limitBytes, countStyle: .memory)
        return "\(usage) / \(limit)"
    }
    return usage
}

private func formatRxTx(rxBytes: Int64?, txBytes: Int64?) -> String? {
    guard let rxBytes, let txBytes else { return nil }
    let rx = ByteCountFormatter.string(fromByteCount: rxBytes, countStyle: .file)
    let tx = ByteCountFormatter.string(fromByteCount: txBytes, countStyle: .file)
    return "\(rx) / \(tx)"
}

func parsePercent(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed.replacingOccurrences(of: "%", with: "")
    return Double(cleaned)
}

private func parseUsageAndLimit(_ text: String) -> (usage: Int64, limit: Int64?)? {
    let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let usage = parseSizeToBytes(parts.first) else { return nil }
    let limit = parts.count > 1 ? parseSizeToBytes(parts[1]) : nil
    return (usage, limit)
}

private func parseRxTx(_ text: String) -> (rx: Int64, tx: Int64)? {
    let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count >= 2,
          let rx = parseSizeToBytes(parts[0]),
          let tx = parseSizeToBytes(parts[1]) else { return nil }
    return (rx, tx)
}

private func parseSizeToBytes(_ text: String?) -> Int64? {
    guard let text else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let tokens = trimmed.split(separator: " ")
    guard let numberPart = tokens.first, let value = Double(numberPart) else { return nil }
    let unit = tokens.count > 1 ? tokens[1].lowercased() : "b"
    let multiplier: Double
    switch unit {
    case "kb", "kib":
        multiplier = 1024
    case "mb", "mib":
        multiplier = 1024 * 1024
    case "gb", "gib":
        multiplier = 1024 * 1024 * 1024
    case "tb", "tib":
        multiplier = 1024 * 1024 * 1024 * 1024
    default:
        multiplier = 1
    }
    return Int64(value * multiplier)
}
