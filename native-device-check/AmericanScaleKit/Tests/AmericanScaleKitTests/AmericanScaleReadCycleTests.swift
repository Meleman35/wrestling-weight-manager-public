import XCTest
@testable import AmericanScaleKit

final class AmericanScaleReadCycleTests: XCTestCase {
    func testReadsWaitForReplyAndThenHalfASecond() {
        var reader = AmericanScaleReadCycle()
        XCTAssertEqual(reader.tick(at: 0, canRead: true), .none)
        reader.start(at: 0)
        XCTAssertEqual(reader.tick(at: 0, canRead: false), .none)
        XCTAssertEqual(reader.tick(at: 0.1, canRead: true), .read)
        XCTAssertEqual(reader.tick(at: 0.8, canRead: true), .none)
        XCTAssertTrue(reader.received(at: 0.9))
        XCTAssertFalse(reader.received(at: 0.91), "Unsolicited callbacks are not read responses")
        XCTAssertEqual(reader.tick(at: 1.39, canRead: true), .none)
        XCTAssertEqual(reader.tick(at: 1.4, canRead: true), .read)
    }
    func testCancelAndRestartDrainsOldReplyWithoutDeliveringIt() {
        var reader = AmericanScaleReadCycle()
        reader.start(at: 0)
        XCTAssertEqual(reader.tick(at: 0.1, canRead: true), .read)
        reader.stop(); reader.start(at: 0.2)
        XCTAssertEqual(reader.tick(at: 0.3, canRead: true), .none)
        XCTAssertFalse(reader.received(at: 0.4))
        XCTAssertEqual(reader.tick(at: 0.9, canRead: true), .read)
        XCTAssertTrue(reader.received(at: 1))
    }
    func testMissingReplyTimesOutWithoutQueuingMoreReads() {
        var reader = AmericanScaleReadCycle()
        reader.start(at: 0)
        XCTAssertEqual(reader.tick(at: 0, canRead: true), .read)
        XCTAssertEqual(reader.tick(at: 1.99, canRead: true), .none)
        XCTAssertEqual(reader.tick(at: 2, canRead: true), .timeout)
        XCTAssertFalse(reader.received(at: 2.01), "Late replies cannot become fresh evidence")
        reader.reset()
        XCTAssertEqual(reader.tick(at: 3, canRead: true), .none)
    }
    func testStoppedReaderDrainsButNeverDeliversOrRequestsAgain() {
        var reader = AmericanScaleReadCycle()
        reader.start(at: 0)
        XCTAssertEqual(reader.tick(at: 0, canRead: true), .read)
        reader.stop()
        XCTAssertTrue(reader.awaitingReply)
        XCTAssertFalse(reader.received(at: 0.1))
        XCTAssertFalse(reader.awaitingReply)
        XCTAssertEqual(reader.tick(at: 10, canRead: true), .none)
    }
}
