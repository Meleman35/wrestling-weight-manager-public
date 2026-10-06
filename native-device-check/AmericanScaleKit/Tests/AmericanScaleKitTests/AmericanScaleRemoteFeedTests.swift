import XCTest
@testable import AmericanScaleKit

final class AmericanScaleRemoteFeedTests: XCTestCase {
    func testNotificationsStayLiveWhileWeightChanges() {
        var feed = AmericanScaleRemoteFeed(); feed.start(at: 0)
        for at in [0.2, 0.6, 1.0, 1.4, 1.8] {
            feed.notificationWeight(at: at); feed.tick(at: at + 0.1)
            XCTAssertTrue(feed.wantsNotifications)
        }
        feed.tick(at: 2.46); XCTAssertFalse(feed.wantsNotifications)
    }
    func testMetadataReadRestoresLiveWeightFeed() {
        var feed = AmericanScaleRemoteFeed(); var reads = AmericanScaleReadCycle()
        feed.start(at: 0); feed.tick(at: 0.7); XCTAssertFalse(feed.wantsNotifications)
        reads.start(at: 0.7)
        XCTAssertEqual(reads.tick(at: 0.7, canRead: false), .none) // Wait for CCC acknowledgement.
        XCTAssertEqual(reads.tick(at: 0.8, canRead: true), .read)
        XCTAssertTrue(reads.received(at: 0.85))
        feed.readReply(hasWeight: false, at: 0.85); reads.stop()
        XCTAssertTrue(feed.wantsNotifications); XCTAssertFalse(reads.awaitingReply)
        feed.notificationWeight(at: 1.0); feed.tick(at: 1.6)
        XCTAssertTrue(feed.wantsNotifications)
        feed.tick(at: 1.66); XCTAssertFalse(feed.wantsNotifications)
        reads.start(at: 1.66)
        XCTAssertEqual(reads.tick(at: 1.7, canRead: true), .read)
        XCTAssertTrue(reads.received(at: 1.75))
        feed.readReply(hasWeight: true, at: 1.75)
        XCTAssertFalse(feed.wantsNotifications) // Stable weights can continue using real reads.
        XCTAssertEqual(reads.tick(at: 2.3, canRead: true), .read)
        XCTAssertEqual(reads.tick(at: 4.31, canRead: true), .timeout)
    }
}
