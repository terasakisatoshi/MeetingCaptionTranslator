import CoreAudio
import XCTest
@testable import MeetingCaptionTranslator

final class CoreAudioTapConfigurationTests: XCTestCase {
    func test_globalStereoTapDescription_isPrivateAndNamed() {
        let configuration = CoreAudioTapConfiguration.defaultConfiguration()
        let description = configuration.tapDescription

        XCTAssertTrue(description.isPrivate)
        XCTAssertEqual(description.name, "MeetingCaptionTranslator Playback Tap")
        XCTAssertTrue(description.isMixdown)
        XCTAssertFalse(description.isMono)
    }

    func test_aggregateDeviceDescription_usesMinimalSampleCompatibleKeysAndFreshUIDs() {
        let configuration = CoreAudioTapConfiguration.defaultConfiguration()
        let firstDescription = configuration.aggregateDeviceDescription as NSDictionary
        let secondDescription = configuration.aggregateDeviceDescription as NSDictionary

        XCTAssertEqual(
            firstDescription[kAudioAggregateDeviceNameKey] as? String,
            "MeetingCaptionTranslator Aggregate Device"
        )
        XCTAssertFalse(
            firstDescription.allKeys.contains { ($0 as? String) == kAudioAggregateDeviceTapAutoStartKey }
        )
        XCTAssertFalse(
            firstDescription.allKeys.contains { ($0 as? String) == kAudioAggregateDeviceIsPrivateKey }
        )
        XCTAssertNotEqual(
            firstDescription[kAudioAggregateDeviceUIDKey] as? String,
            secondDescription[kAudioAggregateDeviceUIDKey] as? String
        )
    }

    func test_composedAggregateDeviceDescription_embedsMainSubdeviceAndTap() {
        let configuration = CoreAudioTapConfiguration.defaultConfiguration()
        let description = configuration.aggregateDeviceDescription(
            mainSubDeviceUID: "output.device.uid",
            tapUID: "tap.uid"
        ) as NSDictionary

        XCTAssertEqual(
            description[kAudioAggregateDeviceMainSubDeviceKey] as? String,
            "output.device.uid"
        )
        XCTAssertEqual(
            ((description[kAudioAggregateDeviceSubDeviceListKey] as? [[String: String]])?.first)?[kAudioSubDeviceUIDKey],
            "output.device.uid"
        )
        XCTAssertEqual(
            ((description[kAudioAggregateDeviceTapListKey] as? [[String: String]])?.first)?[kAudioSubTapUIDKey],
            "tap.uid"
        )
        XCTAssertEqual(
            description[kAudioAggregateDeviceIsPrivateKey] as? NSNumber,
            1
        )
    }

    func test_throwIfError_mapsDevicePermissionsError() {
        XCTAssertThrowsError(
            try CoreAudioHardwareClient.throwIfError(kAudioDevicePermissionsError, context: "start")
        ) { error in
            XCTAssertEqual(error as? CoreAudioTapError, .permissionDenied(context: "start"))
        }
    }

    func test_appendingUIDToAggregateList_preservesExistingPropertySizeAndAddsOneEntry() {
        let initialPropertySize = UInt32(MemoryLayout<CFString>.stride)
        let result = CoreAudioHardwareClient.appendingUID(
            "device.two",
            toAggregateUIDList: ["device.one" as CFString],
            currentPropertySize: initialPropertySize
        )

        XCTAssertEqual(result.list as? [String], ["device.one", "device.two"])
        XCTAssertEqual(
            result.propertySize,
            initialPropertySize + UInt32(MemoryLayout<CFString>.stride)
        )
    }

    func test_appendingDuplicateUIDToAggregateList_keepsOriginalPropertySize() {
        let initialPropertySize = UInt32(MemoryLayout<CFString>.stride * 2)
        let result = CoreAudioHardwareClient.appendingUID(
            "device.one",
            toAggregateUIDList: ["device.one" as CFString],
            currentPropertySize: initialPropertySize
        )

        XCTAssertEqual(result.list as? [String], ["device.one"])
        XCTAssertEqual(result.propertySize, initialPropertySize)
    }
}
