import CoreAudio
import Foundation

struct CoreAudioTapConfiguration {
    static let aggregateDeviceUIDPrefix = "atelierarith.MeetingCaptionTranslator.aggregate."

    let tapName: String
    let aggregateDeviceName: String

    static func defaultConfiguration() -> CoreAudioTapConfiguration {
        CoreAudioTapConfiguration(
            tapName: "MeetingCaptionTranslator Playback Tap",
            aggregateDeviceName: "MeetingCaptionTranslator Aggregate Device"
        )
    }

    var tapDescription: CATapDescription {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = tapName
        description.isPrivate = true
        return description
    }

    var aggregateDeviceDescription: CFDictionary {
        [
            kAudioAggregateDeviceNameKey: aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: "\(Self.aggregateDeviceUIDPrefix)\(UUID().uuidString)"
        ] as CFDictionary
    }

    func aggregateDeviceDescription(
        mainSubDeviceUID: String,
        tapUID: String
    ) -> CFDictionary {
        [
            kAudioAggregateDeviceNameKey: aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: "\(Self.aggregateDeviceUIDPrefix)\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: mainSubDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: mainSubDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ]
        ] as CFDictionary
    }
}
