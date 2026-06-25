import XCTest
@testable import iContainer

final class ContainerLogAccumulatorTests: XCTestCase {
    func testFirstSnapshotIsDisplayedInsteadOfOnlyStoredAsBaseline() {
        var accumulator = ContainerLogAccumulator()

        accumulator.ingest("""
        2026-06-25T09:00:00Z first
        2026-06-25T09:00:01Z second
        """)

        XCTAssertEqual(
            accumulator.text,
            "2026-06-25T09:00:00Z first\n2026-06-25T09:00:01Z second"
        )
    }

    func testSubsequentSnapshotAppendsOnlyNewLines() {
        var accumulator = ContainerLogAccumulator()
        accumulator.ingest("""
        2026-06-25T09:00:00Z first
        2026-06-25T09:00:01Z second
        """)

        accumulator.ingest("""
        2026-06-25T09:00:00Z first
        2026-06-25T09:00:01Z second
        2026-06-25T09:00:02Z third
        """)

        XCTAssertEqual(
            accumulator.text,
            "2026-06-25T09:00:00Z first\n2026-06-25T09:00:01Z second\n2026-06-25T09:00:02Z third"
        )
    }

    func testClearDropsOlderTimestampedLinesButKeepsNewUntimestampedLines() throws {
        var accumulator = ContainerLogAccumulator()
        accumulator.ingest("2026-06-25T09:00:00Z before")
        let clearDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-25T09:00:01Z"))

        accumulator.clear(at: clearDate)
        accumulator.ingest("""
        2026-06-25T09:00:00Z before
        2026-06-25T09:00:02Z after
        untimestamped after clear
        """)

        XCTAssertEqual(
            accumulator.text,
            "2026-06-25T09:00:02Z after\nuntimestamped after clear"
        )
    }
}
