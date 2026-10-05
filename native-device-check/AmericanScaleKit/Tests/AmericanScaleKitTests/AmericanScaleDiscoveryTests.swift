import Foundation
import XCTest
@testable import AmericanScaleKit

final class AmericanScaleDiscoveryTests: XCTestCase {
    let scale = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let other = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testRecognizesScaleServiceInAllBluetoothUUIDForms() {
        for service in ["108D", "108d", "0000108D", "0000108d-0000-1000-8000-00805f9b34fb"] {
            XCTAssertTrue(AmericanScaleDiscovery.includes(identifier: scale, advertisedServices: ["180F", service], knownScaleIdentifiers: []))
        }
    }
    func testExcludesUnrelatedBluetoothIncludingNFCReadersAndUnnamedDevices() {
        for services in [[], ["180F"], ["180D"], ["00003970-817C-48DF-8DB2-476A8134EDE0"], ["108E"], ["0000108D-1234-1000-8000-00805F9B34FB"]] {
            XCTAssertFalse(AmericanScaleDiscovery.includes(identifier: other, advertisedServices: services, knownScaleIdentifiers: []))
        }
    }
    func testPreviouslyVerifiedRenamedScaleRemainsDiscoverableWithoutServiceAdvertisement() {
        XCTAssertTrue(AmericanScaleDiscovery.includes(identifier: scale, advertisedServices: [], knownScaleIdentifiers: [scale]))
        XCTAssertFalse(AmericanScaleDiscovery.includes(identifier: other, advertisedServices: [], knownScaleIdentifiers: [scale]))
    }
    func testNewSupportedScaleStillAppearsAlongsideSavedScale() {
        XCTAssertTrue(AmericanScaleDiscovery.includes(identifier: other, advertisedServices: ["108D"], knownScaleIdentifiers: [scale]))
    }
}
