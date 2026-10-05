#if canImport(CoreBluetooth) && canImport(Combine)
import Combine
import XCTest
@testable import AmericanScaleKit

@MainActor final class AmericanScaleClientTests: XCTestCase {
    func testViewTeardownCanStopReadsWithoutPublishingDuringViewUpdate() async {
        await MainActor.run {
            let client = AmericanScaleClient(startBluetooth: false)
            var publications = 0
            let subscription = client.objectWillChange.sink { publications += 1 }
            // The controller's stop and observer-removal callbacks both run
            // during representable teardown. Neither may publish a view change.
            client.setRemoteWeightReadingEnabled(false)
            client.onRemoteWeightPacket = nil
            client.setRemoteWeightReadingEnabled(false)
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(client.remoteReadStatus, "Direct scale reads inactive.")
            XCTAssertNil(client.onRemoteWeightPacket)
            withExtendedLifetime(subscription) {}
        }
    }
}
#endif
