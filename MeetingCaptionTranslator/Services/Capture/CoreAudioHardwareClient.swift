import CoreAudio
import Foundation

enum CoreAudioTapError: Error, Equatable, LocalizedError {
    case permissionDenied(context: String)
    case osStatus(OSStatus, context: String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let context):
            "System Audio Recording permission denied while attempting to \(context)"
        case .osStatus(let status, let context):
            "Core Audio failed to \(context) (OSStatus \(status) / 0x\(Self.hexString(for: status)))"
        }
    }

    private static func hexString(for status: OSStatus) -> String {
        String(format: "%08X", UInt32(bitPattern: Int32(status)))
    }
}

protocol CoreAudioPlaybackHardware: AnyObject {
    func destroyAggregateDevices(uidPrefix: String) throws

    func createTap(description: CATapDescription) throws -> AudioObjectID
    func destroyTap(_ tapID: AudioObjectID)

    func createAggregateDevice(description: CFDictionary) throws -> AudioObjectID
    func destroyAggregateDevice(_ deviceID: AudioObjectID)

    func defaultOutputDeviceUID() throws -> String
    func tapUID(for tapID: AudioObjectID) throws -> String
    func tapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription
    func addSubDevice(_ deviceUID: String, toAggregateDevice deviceID: AudioObjectID) throws
    func addTap(_ tapUID: String, toAggregateDevice deviceID: AudioObjectID) throws
    func activeSubDeviceCount(onAggregateDevice deviceID: AudioObjectID) throws -> Int
    func activeSubTapCount(onAggregateDevice deviceID: AudioObjectID) throws -> Int

    func createIOProcID(
        deviceID: AudioObjectID,
        ioProc: AudioDeviceIOProc,
        clientData: UnsafeMutableRawPointer?
    ) throws -> AudioDeviceIOProcID
    func destroyIOProcID(_ ioProcID: AudioDeviceIOProcID, deviceID: AudioObjectID)

    func start(deviceID: AudioObjectID, ioProcID: AudioDeviceIOProcID) throws
    func stop(deviceID: AudioObjectID, ioProcID: AudioDeviceIOProcID)
}

final class DefaultCoreAudioPlaybackHardware: CoreAudioPlaybackHardware {
    func destroyAggregateDevices(uidPrefix: String) throws {
        let deviceIDs = try allDeviceIDs()

        for deviceID in deviceIDs {
            let transportType = try? deviceTransportType(for: deviceID)
            guard transportType == kAudioDeviceTransportTypeAggregate else {
                continue
            }

            guard let deviceUID = try? deviceUID(for: deviceID),
                  deviceUID.hasPrefix(uidPrefix)
            else {
                continue
            }

            _ = AudioHardwareDestroyAggregateDevice(deviceID)
        }
    }

    func createTap(description: CATapDescription) throws -> AudioObjectID {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioHardwareClient.throwIfError(
            AudioHardwareCreateProcessTap(description, &tapID),
            context: "create tap"
        )
        return tapID
    }

    func destroyTap(_ tapID: AudioObjectID) {
        _ = AudioHardwareDestroyProcessTap(tapID)
    }

    func createAggregateDevice(description: CFDictionary) throws -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioHardwareClient.throwIfError(
            AudioHardwareCreateAggregateDevice(description, &deviceID),
            context: "create aggregate device"
        )
        return deviceID
    }

    func destroyAggregateDevice(_ deviceID: AudioObjectID) {
        _ = AudioHardwareDestroyAggregateDevice(deviceID)
    }

    func defaultOutputDeviceUID() throws -> String {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var deviceID = AudioObjectID(kAudioObjectUnknown)

        try CoreAudioHardwareClient.throwIfError(
            withUnsafeMutablePointer(to: &deviceID) { pointer in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    0,
                    nil,
                    &propertySize,
                    pointer
                )
            },
            context: "get default output device"
        )

        guard deviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw CoreAudioTapError.osStatus(kAudioHardwareBadObjectError, context: "get default output device")
        }

        return try deviceUID(for: deviceID)
    }

    func tapUID(for tapID: AudioObjectID) throws -> String {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioTapPropertyUID)
        var propertySize = UInt32(MemoryLayout<CFString?>.size)
        var tapUID: CFString?

        try CoreAudioHardwareClient.throwIfError(
            withUnsafeMutablePointer(to: &tapUID) { pointer in
                AudioObjectGetPropertyData(
                    tapID,
                    &address,
                    0,
                    nil,
                    &propertySize,
                    pointer
                )
            },
            context: "get tap uid"
        )

        guard let tapUID else {
            throw CoreAudioTapError.osStatus(kAudioHardwareUnspecifiedError, context: "get tap uid")
        }

        return tapUID as String
    }

    func tapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioTapPropertyFormat)
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var format = AudioStreamBasicDescription()

        try CoreAudioHardwareClient.throwIfError(
            withUnsafeMutablePointer(to: &format) { pointer in
                AudioObjectGetPropertyData(
                    tapID,
                    &address,
                    0,
                    nil,
                    &propertySize,
                    pointer
                )
            },
            context: "get tap format"
        )

        return format
    }

    func addSubDevice(_ deviceUID: String, toAggregateDevice deviceID: AudioObjectID) throws {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioAggregateDevicePropertyFullSubDeviceList)
        var propertySize: UInt32 = 0
        let addContext = "set aggregate subdevice list for \(deviceUID)"

        try CoreAudioHardwareClient.throwIfError(
            AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize),
            context: "get aggregate subdevice list size"
        )

        var deviceList: [CFString] = []

        if propertySize > 0 {
            var existingList: CFArray?
            try CoreAudioHardwareClient.throwIfError(
                withUnsafeMutablePointer(to: &existingList) { pointer in
                    AudioObjectGetPropertyData(
                        deviceID,
                        &address,
                        0,
                        nil,
                        &propertySize,
                        pointer
                    )
                },
                context: "get aggregate subdevice list"
            )

            deviceList = existingList as? [CFString] ?? []
        }

        let deviceUID = deviceUID as CFString
        let mutation = CoreAudioHardwareClient.appendingUID(
            deviceUID as String,
            toAggregateUIDList: deviceList,
            currentPropertySize: propertySize
        )
        var updatedList = mutation.list
        propertySize = mutation.propertySize

        try CoreAudioHardwareClient.throwIfError(
            withUnsafePointer(to: &updatedList) { pointer in
                AudioObjectSetPropertyData(
                    deviceID,
                    &address,
                    0,
                    nil,
                    propertySize,
                    pointer
                )
            },
            context: addContext
        )
    }

    func addTap(_ tapUID: String, toAggregateDevice deviceID: AudioObjectID) throws {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioAggregateDevicePropertyTapList)
        var propertySize: UInt32 = 0
        let addContext = "set aggregate tap list for \(tapUID)"

        try CoreAudioHardwareClient.throwIfError(
            AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize),
            context: "get aggregate tap list size"
        )

        var tapList: [CFString] = []

        if propertySize > 0 {
            var existingList: CFArray?
            try CoreAudioHardwareClient.throwIfError(
                withUnsafeMutablePointer(to: &existingList) { pointer in
                    AudioObjectGetPropertyData(
                        deviceID,
                        &address,
                        0,
                        nil,
                        &propertySize,
                        pointer
                    )
                },
                context: "get aggregate tap list"
            )

            tapList = existingList as? [CFString] ?? []
        }

        let tapUID = tapUID as CFString
        let mutation = CoreAudioHardwareClient.appendingUID(
            tapUID as String,
            toAggregateUIDList: tapList,
            currentPropertySize: propertySize
        )
        var updatedList = mutation.list
        propertySize = mutation.propertySize

        try CoreAudioHardwareClient.throwIfError(
            withUnsafePointer(to: &updatedList) { pointer in
                AudioObjectSetPropertyData(
                    deviceID,
                    &address,
                    0,
                    nil,
                    propertySize,
                    pointer
                )
            },
            context: addContext
        )
    }

    func activeSubDeviceCount(onAggregateDevice deviceID: AudioObjectID) throws -> Int {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioAggregateDevicePropertyActiveSubDeviceList)
        var propertySize: UInt32 = 0

        try CoreAudioHardwareClient.throwIfError(
            AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize),
            context: "get aggregate active subdevice list size"
        )

        guard propertySize > 0 else {
            return 0
        }

        let subDeviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.stride
        var subDeviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: subDeviceCount)

        try CoreAudioHardwareClient.throwIfError(
            subDeviceIDs.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return kAudioHardwareUnspecifiedError
                }

                return AudioObjectGetPropertyData(
                    deviceID,
                    &address,
                    0,
                    nil,
                    &propertySize,
                    baseAddress
                )
            },
            context: "get aggregate active subdevice list"
        )

        return Int(propertySize) / MemoryLayout<AudioObjectID>.stride
    }

    func activeSubTapCount(onAggregateDevice deviceID: AudioObjectID) throws -> Int {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioAggregateDevicePropertySubTapList)
        var propertySize: UInt32 = 0

        try CoreAudioHardwareClient.throwIfError(
            AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize),
            context: "get aggregate active sub tap list size"
        )

        guard propertySize > 0 else {
            return 0
        }

        let subTapCount = Int(propertySize) / MemoryLayout<AudioObjectID>.stride
        var subTapIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: subTapCount)

        try CoreAudioHardwareClient.throwIfError(
            subTapIDs.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return kAudioHardwareUnspecifiedError
                }

                return AudioObjectGetPropertyData(
                    deviceID,
                    &address,
                    0,
                    nil,
                    &propertySize,
                    baseAddress
                )
            },
            context: "get aggregate active sub tap list"
        )

        return Int(propertySize) / MemoryLayout<AudioObjectID>.stride
    }

    func createIOProcID(
        deviceID: AudioObjectID,
        ioProc: AudioDeviceIOProc,
        clientData: UnsafeMutableRawPointer?
    ) throws -> AudioDeviceIOProcID {
        var ioProcID: AudioDeviceIOProcID?

        try CoreAudioHardwareClient.throwIfError(
            AudioDeviceCreateIOProcID(deviceID, ioProc, clientData, &ioProcID),
            context: "create io proc"
        )

        guard let ioProcID else {
            throw CoreAudioTapError.osStatus(kAudioHardwareUnspecifiedError, context: "create io proc")
        }

        return ioProcID
    }

    func destroyIOProcID(_ ioProcID: AudioDeviceIOProcID, deviceID: AudioObjectID) {
        _ = AudioDeviceDestroyIOProcID(deviceID, ioProcID)
    }

    func start(deviceID: AudioObjectID, ioProcID: AudioDeviceIOProcID) throws {
        try CoreAudioHardwareClient.throwIfError(
            AudioDeviceStart(deviceID, ioProcID),
            context: "start io"
        )
    }

    func stop(deviceID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {
        _ = AudioDeviceStop(deviceID, ioProcID)
    }

    private func allDeviceIDs() throws -> [AudioObjectID] {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioHardwarePropertyDevices)
        var propertySize: UInt32 = 0

        try CoreAudioHardwareClient.throwIfError(
            AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize),
            context: "get all device ids size"
        )

        let deviceCount = Int(propertySize) / MemoryLayout<AudioObjectID>.stride
        var deviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: deviceCount)

        try CoreAudioHardwareClient.throwIfError(
            deviceIDs.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return kAudioHardwareUnspecifiedError
                }

                return AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    0,
                    nil,
                    &propertySize,
                    baseAddress
                )
            },
            context: "get all device ids"
        )

        return deviceIDs
    }

    private func deviceTransportType(for deviceID: AudioObjectID) throws -> UInt32 {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioDevicePropertyTransportType)
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var transportType: UInt32 = 0

        try CoreAudioHardwareClient.throwIfError(
            withUnsafeMutablePointer(to: &transportType) { pointer in
                AudioObjectGetPropertyData(
                    deviceID,
                    &address,
                    0,
                    nil,
                    &propertySize,
                    pointer
                )
            },
            context: "get device transport type"
        )

        return transportType
    }

    private func deviceUID(for deviceID: AudioObjectID) throws -> String {
        var address = CoreAudioHardwareClient.propertyAddress(selector: kAudioDevicePropertyDeviceUID)
        var propertySize = UInt32(MemoryLayout<CFString?>.size)
        var deviceUID: CFString?

        try CoreAudioHardwareClient.throwIfError(
            withUnsafeMutablePointer(to: &deviceUID) { pointer in
                AudioObjectGetPropertyData(
                    deviceID,
                    &address,
                    0,
                    nil,
                    &propertySize,
                    pointer
                )
            },
            context: "get device uid"
        )

        guard let deviceUID else {
            throw CoreAudioTapError.osStatus(kAudioHardwareUnspecifiedError, context: "get device uid")
        }

        return deviceUID as String
    }
}

enum CoreAudioHardwareClient {
    static func throwIfError(_ status: OSStatus, context: String) throws {
        guard status != noErr else {
            return
        }

        if status == kAudioDevicePermissionsError {
            throw CoreAudioTapError.permissionDenied(context: context)
        }

        throw CoreAudioTapError.osStatus(status, context: context)
    }

    static func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    static func appendingUID(
        _ uid: String,
        toAggregateUIDList currentList: [CFString],
        currentPropertySize: UInt32
    ) -> (list: CFArray, propertySize: UInt32) {
        var updatedList = currentList
        var updatedPropertySize = currentPropertySize
        let uid = uid as CFString

        if !updatedList.contains(uid) {
            updatedList.append(uid)
            updatedPropertySize += UInt32(MemoryLayout<CFString>.stride)
        }

        return (updatedList as CFArray, updatedPropertySize)
    }
}
