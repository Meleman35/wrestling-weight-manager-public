import XCTest
@testable import AmericanScaleKit

final class AmericanScaleProtocolTests: XCTestCase {
    func testPositiveWeightParsing() {
        var parser = AmericanScaleStreamParser()
        XCTAssertEqual(parser.append(Data("Weight=184.400######".utf8)), [.weight(184.4)])
    }

    func testZeroWeightParsing() {
        var parser = AmericanScaleStreamParser()
        XCTAssertEqual(parser.append(Data("Weight=0.000########".utf8)), [.weight(0.0)])
    }

    func testNegativeWeightParsing() {
        var parser = AmericanScaleStreamParser()
        XCTAssertEqual(parser.append(Data("Weight=-68.200######".utf8)), [.weight(-68.2)])
    }

    func testBatteryCapacityAndLockInParsing() {
        var parser = AmericanScaleStreamParser()
        let input = "BatteryLevel=70.000#Capacity=400.000####Lockin=0.000#######"
        XCTAssertEqual(
            parser.append(Data(input.utf8)),
            [.batteryLevel(70), .capacity(400), .lockInState(0)]
        )
    }

    func testRepeatedHashPaddingCreatesNoEmptyMessages() {
        var parser = AmericanScaleStreamParser()
        XCTAssertEqual(parser.append(Data("Weight=5.600###########".utf8)), [.weight(5.6)])
        XCTAssertEqual(parser.append(Data("########".utf8)), [])
    }

    func testMultipleRecordsInSingleChunk() {
        var parser = AmericanScaleStreamParser()
        let input = "Weight=120.500#BatteryLevel=68.000#Info=Ready#"
        XCTAssertEqual(
            parser.append(Data(input.utf8)),
            [.weight(120.5), .batteryLevel(68), .info("Ready")]
        )
    }

    func testArbitraryFragmentBoundaries() {
        var parser = AmericanScaleStreamParser()

        XCTAssertEqual(parser.append(Data("Wei".utf8)), [])
        XCTAssertEqual(parser.append(Data("ght=-37".utf8)), [])
        XCTAssertEqual(parser.append(Data(".800##".utf8)), [.weight(-37.8)])
        XCTAssertEqual(parser.bufferedByteCount, 0)
    }

    func testFragmentedCalibrationInfoExample() {
        var parser = AmericanScaleStreamParser()

        XCTAssertEqual(parser.append(Data("Info=Press Calibrate".utf8)), [])
        XCTAssertEqual(parser.append(Data(" to start the proces".utf8)), [])
        XCTAssertEqual(
            parser.append(Data("s###################".utf8)),
            [.info("Press Calibrate to start the process")]
        )
    }

    func testExactZeroCommandBytes() {
        XCTAssertEqual(
            Array(AmericanScaleCommand.zero),
            [0x5A, 0x65, 0x72, 0x6F, 0x3D, 0x31, 0x23]
        )
    }

    func testExactLockInCommandBytes() {
        XCTAssertEqual(
            Array(AmericanScaleCommand.lockIn),
            [0x4C, 0x6F, 0x63, 0x6B, 0x69, 0x6E, 0x3D, 0x31, 0x23]
        )
    }

    func testExactRenameCommandBytes() throws {
        let command = try AmericanScaleCommand.rename("wm-test")
        XCTAssertEqual(String(decoding: command, as: UTF8.self), "DeviceName=wm-test#")
    }

    func testRenameValidation() throws {
        XCTAssertThrowsError(try AmericanScaleCommand.rename("")) { error in
            XCTAssertEqual(error as? AmericanScaleRenameValidationError, .empty)
        }

        XCTAssertThrowsError(try AmericanScaleCommand.rename("abcdefghi")) { error in
            XCTAssertEqual(error as? AmericanScaleRenameValidationError, .tooLong(maxBytes: 8))
        }

        XCTAssertThrowsError(try AmericanScaleCommand.rename("bad#name")) { error in
            XCTAssertEqual(error as? AmericanScaleRenameValidationError, .containsDelimiter)
        }

        XCTAssertThrowsError(try AmericanScaleCommand.rename("é")) { error in
            XCTAssertEqual(error as? AmericanScaleRenameValidationError, .nonASCII)
        }

        XCTAssertNoThrow(try AmericanScaleCommand.rename("Lyman"))
    }

    func testPoundsToKilogramsConversion() {
        XCTAssertEqual(
            AmericanScaleUnits.kilograms(fromPounds: 37.8),
            17.1457915864,
            accuracy: 0.0000001
        )
    }

    func testLockInIsOneShotAndLiveStreamContinues() {
        var state = AmericanScaleSessionState()
        state.apply(.weight(5.4))
        state.armLockIn()
        state.apply(.weight(5.6))

        XCTAssertEqual(state.lockedWeightLb, 5.6)
        XCTAssertFalse(state.pendingLockIn)
        XCTAssertEqual(state.liveWeightLb, 5.6)

        state.apply(.weight(0.0))
        XCTAssertEqual(state.liveWeightLb, 0.0)
        XCTAssertEqual(state.lockedWeightLb, 5.6)
    }
}
