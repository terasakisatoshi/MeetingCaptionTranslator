import AVFoundation
import CoreAudio
import CoreMedia
import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class SystemPlaybackCaptureServiceTests: XCTestCase {
    func test_startCapture_createsTapAndStartsHardware() async throws {
        let hardware = FakeCoreAudioPlaybackHardware()
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })

        XCTAssertEqual(hardware.destroyedAggregateDeviceUIDPrefix, CoreAudioTapConfiguration.aggregateDeviceUIDPrefix)
        XCTAssertEqual(hardware.createdTapCount, 1)
        XCTAssertEqual(hardware.createdAggregateDeviceCount, 1)
        XCTAssertEqual(
            hardware.createdAggregateDeviceDescription?[kAudioAggregateDeviceMainSubDeviceKey] as? String,
            hardware.defaultOutputDeviceUIDValue
        )
        XCTAssertEqual(
            ((hardware.createdAggregateDeviceDescription?[kAudioAggregateDeviceSubDeviceListKey] as? [[String: String]])?.first)?[kAudioSubDeviceUIDKey],
            hardware.defaultOutputDeviceUIDValue
        )
        XCTAssertEqual(
            ((hardware.createdAggregateDeviceDescription?[kAudioAggregateDeviceTapListKey] as? [[String: String]])?.first)?[kAudioSubTapUIDKey],
            hardware.tapUIDValue
        )
        XCTAssertGreaterThanOrEqual(hardware.activeSubDeviceCountQueryCount, 1)
        XCTAssertGreaterThanOrEqual(hardware.activeSubTapCountQueryCount, 1)
        XCTAssertTrue(hardware.didCreateIOProcWithoutQueue)
        XCTAssertTrue(hardware.didStartIO)
    }

    func test_startCapture_waitsForAggregateActivationBeforeStartingHardware() async throws {
        let hardware = FakeCoreAudioPlaybackHardware(
            subDeviceActivationPollsRequired: 2,
            subTapActivationPollsRequired: 3
        )
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })

        XCTAssertEqual(hardware.activeSubDeviceCountQueryCount, 3)
        XCTAssertEqual(hardware.activeSubTapCountQueryCount, 3)
        XCTAssertTrue(hardware.didStartIO)
    }

    func test_startCapture_cleansUpTapWhenTapFormatFails() async {
        let hardware = FakeCoreAudioPlaybackHardware(failurePoint: .tapFormat)
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        do {
            try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })
            XCTFail("Expected startCapture to throw")
        } catch {
            XCTAssertTrue(hardware.didDestroyTap)
            XCTAssertFalse(hardware.didDestroyAggregateDevice)
            XCTAssertFalse(hardware.didDestroyIOProcID)
        }
    }

    func test_startCapture_cleansUpTapWhenCreateAggregateDeviceFails() async {
        let hardware = FakeCoreAudioPlaybackHardware(failurePoint: .createAggregateDevice)
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        do {
            try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })
            XCTFail("Expected startCapture to throw")
        } catch {
            XCTAssertTrue(hardware.didDestroyTap)
            XCTAssertFalse(hardware.didDestroyAggregateDevice)
            XCTAssertFalse(hardware.didDestroyIOProcID)
        }
    }

    func test_startCapture_cleansUpTapWhenTapUIDFailsBeforeAggregateCreation() async {
        let hardware = FakeCoreAudioPlaybackHardware(failurePoint: .tapUID)
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        do {
            try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })
            XCTFail("Expected startCapture to throw")
        } catch {
            XCTAssertTrue(hardware.didDestroyTap)
            XCTAssertFalse(hardware.didDestroyAggregateDevice)
            XCTAssertFalse(hardware.didDestroyIOProcID)
        }
    }

    func test_startCapture_cleansUpTapAndAggregateDeviceWhenCreateIOProcIDFails() async {
        let hardware = FakeCoreAudioPlaybackHardware(failurePoint: .createIOProcID)
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        do {
            try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })
            XCTFail("Expected startCapture to throw")
        } catch {
            XCTAssertTrue(hardware.didDestroyTap)
            XCTAssertTrue(hardware.didDestroyAggregateDevice)
            XCTAssertFalse(hardware.didDestroyIOProcID)
        }
    }

    func test_startCapture_cleansUpTapAggregateDeviceAndIOProcWhenStartFails() async {
        let hardware = FakeCoreAudioPlaybackHardware(failurePoint: .start)
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        do {
            try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })
            XCTFail("Expected startCapture to throw")
        } catch {
            XCTAssertTrue(hardware.didDestroyTap)
            XCTAssertTrue(hardware.didDestroyAggregateDevice)
            XCTAssertTrue(hardware.didDestroyIOProcID)
            XCTAssertTrue(hardware.didStopIO)
        }
    }

    func test_stopCapture_stopsAndDestroysCreatedObjects() async throws {
        let hardware = FakeCoreAudioPlaybackHardware()
        let service = SystemPlaybackCaptureService(
            hardware: hardware,
            configuration: .defaultConfiguration(),
            bufferBuilder: PlaybackPCMBufferBuilder()
        )

        try await service.startCapture(inputHandler: { _ in }, errorHandler: { _ in })
        await service.stopCapture()

        XCTAssertTrue(hardware.didStopIO)
        XCTAssertTrue(hardware.didDestroyIOProcID)
        XCTAssertTrue(hardware.didDestroyAggregateDevice)
        XCTAssertTrue(hardware.didDestroyTap)
    }
}

private final class FakeCoreAudioPlaybackHardware: CoreAudioPlaybackHardware {
    enum FailurePoint {
        case tapFormat
        case createAggregateDevice
        case defaultOutputDeviceUID
        case addSubDevice
        case tapUID
        case addTap
        case createIOProcID
        case start
    }

    private(set) var createdTapCount = 0
    private(set) var createdAggregateDeviceCount = 0
    private(set) var didStartIO = false
    private(set) var didStopIO = false
    private(set) var didDestroyIOProcID = false
    private(set) var didDestroyAggregateDevice = false
    private(set) var didDestroyTap = false
    private(set) var activeSubDeviceCountQueryCount = 0
    private(set) var activeSubTapCountQueryCount = 0
    private(set) var didCreateIOProcWithoutQueue = false
    private(set) var addedSubDeviceUID: String?
    private(set) var createdAggregateDeviceDescription: [String: Any]?
    private(set) var destroyedAggregateDeviceUIDPrefix: String?
    private let failurePoint: FailurePoint?
    private let subDeviceActivationPollsRequired: Int
    private let subTapActivationPollsRequired: Int

    private let tapID: AudioObjectID = 101
    private let aggregateDeviceID: AudioObjectID = 202
    private let ioProcID: AudioDeviceIOProcID = fakeAudioDeviceIOProc
    let defaultOutputDeviceUIDValue = "test.output.device.uid"
    let tapUIDValue = "test.tap.uid"
    private let tapUID = "test.tap.uid" as CFString
    private let format = AudioStreamBasicDescription(
        mSampleRate: 48_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8,
        mFramesPerPacket: 1,
        mBytesPerFrame: 8,
        mChannelsPerFrame: 2,
        mBitsPerChannel: 32,
        mReserved: 0
    )

    init(
        failurePoint: FailurePoint? = nil,
        subDeviceActivationPollsRequired: Int = 1,
        subTapActivationPollsRequired: Int = 1
    ) {
        self.failurePoint = failurePoint
        self.subDeviceActivationPollsRequired = subDeviceActivationPollsRequired
        self.subTapActivationPollsRequired = subTapActivationPollsRequired
    }

    func createTap(description: CATapDescription) throws -> AudioObjectID {
        createdTapCount += 1
        return tapID
    }

    func destroyAggregateDevices(uidPrefix: String) throws {
        destroyedAggregateDeviceUIDPrefix = uidPrefix
    }

    func destroyTap(_ tapID: AudioObjectID) {
        XCTAssertEqual(tapID, self.tapID)
        didDestroyTap = true
    }

    func createAggregateDevice(description: CFDictionary) throws -> AudioObjectID {
        if failurePoint == .createAggregateDevice {
            throw TestError.injectedFailure
        }

        createdAggregateDeviceCount += 1
        createdAggregateDeviceDescription = description as? [String: Any]
        return aggregateDeviceID
    }

    func destroyAggregateDevice(_ deviceID: AudioObjectID) {
        XCTAssertEqual(deviceID, aggregateDeviceID)
        didDestroyAggregateDevice = true
    }

    func defaultOutputDeviceUID() throws -> String {
        if failurePoint == .defaultOutputDeviceUID {
            throw TestError.injectedFailure
        }

        return defaultOutputDeviceUIDValue
    }

    func tapUID(for tapID: AudioObjectID) throws -> String {
        XCTAssertEqual(tapID, self.tapID)
        if failurePoint == .tapUID {
            throw TestError.injectedFailure
        }

        return tapUID as String
    }

    func tapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        XCTAssertEqual(tapID, self.tapID)
        if failurePoint == .tapFormat {
            throw TestError.injectedFailure
        }

        return format
    }

    func addSubDevice(_ deviceUID: String, toAggregateDevice deviceID: AudioObjectID) throws {
        XCTAssertEqual(deviceUID, defaultOutputDeviceUIDValue)
        XCTAssertEqual(deviceID, aggregateDeviceID)
        if failurePoint == .addSubDevice {
            throw TestError.injectedFailure
        }

        addedSubDeviceUID = deviceUID
    }

    func addTap(_ tapUID: String, toAggregateDevice deviceID: AudioObjectID) throws {
        XCTAssertEqual(tapUID, self.tapUID as String)
        XCTAssertEqual(deviceID, aggregateDeviceID)
        if failurePoint == .addTap {
            throw TestError.injectedFailure
        }
    }

    func activeSubDeviceCount(onAggregateDevice deviceID: AudioObjectID) throws -> Int {
        XCTAssertEqual(deviceID, aggregateDeviceID)
        activeSubDeviceCountQueryCount += 1
        if activeSubDeviceCountQueryCount >= subDeviceActivationPollsRequired {
            return 1
        }

        return 0
    }

    func activeSubTapCount(onAggregateDevice deviceID: AudioObjectID) throws -> Int {
        XCTAssertEqual(deviceID, aggregateDeviceID)
        activeSubTapCountQueryCount += 1
        if activeSubTapCountQueryCount >= subTapActivationPollsRequired {
            return 1
        }

        return 0
    }

    func createIOProcID(
        deviceID: AudioObjectID,
        ioProc: AudioDeviceIOProc,
        clientData: UnsafeMutableRawPointer?
    ) throws -> AudioDeviceIOProcID {
        XCTAssertEqual(deviceID, aggregateDeviceID)
        XCTAssertNotNil(clientData)
        if failurePoint == .createIOProcID {
            throw TestError.injectedFailure
        }

        let callbackPointer = unsafeBitCast(ioProc, to: UnsafeRawPointer.self)
        XCTAssertNotEqual(callbackPointer, UnsafeRawPointer(bitPattern: 0))
        didCreateIOProcWithoutQueue = true
        return ioProcID
    }

    func destroyIOProcID(_ ioProcID: AudioDeviceIOProcID, deviceID: AudioObjectID) {
        XCTAssertEqual(deviceID, aggregateDeviceID)
        assertSameIOProcID(ioProcID, self.ioProcID)
        didDestroyIOProcID = true
    }

    func start(deviceID: AudioObjectID, ioProcID: AudioDeviceIOProcID) throws {
        XCTAssertEqual(deviceID, aggregateDeviceID)
        assertSameIOProcID(ioProcID, self.ioProcID)
        if failurePoint == .start {
            throw TestError.injectedFailure
        }

        didStartIO = true
    }

    func stop(deviceID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {
        XCTAssertEqual(deviceID, aggregateDeviceID)
        assertSameIOProcID(ioProcID, self.ioProcID)
        didStopIO = true
    }
}

private enum TestError: Error {
    case injectedFailure
}

private func assertSameIOProcID(
    _ lhs: AudioDeviceIOProcID,
    _ rhs: AudioDeviceIOProcID,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let lhsPointer = unsafeBitCast(lhs, to: UnsafeRawPointer.self)
    let rhsPointer = unsafeBitCast(rhs, to: UnsafeRawPointer.self)
    XCTAssertEqual(lhsPointer, rhsPointer, file: file, line: line)
}

private func fakeAudioDeviceIOProc(
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    noErr
}
