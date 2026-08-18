import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct SDKDeviceReportRequest: Encodable, Sendable {

    let device: DeviceInfo
    let sdkStatus: String
    let blockReason: String

    init(
        device: DeviceInfo,
        sdkStatus: String,
        blockReason: String
    ) {
        self.device = device
        self.sdkStatus = sdkStatus
        self.blockReason = blockReason
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case bundleId = "bundle_id"
        case hasSim = "has_sim"
        case simCountry = "sim_country"
        case detectedPackages = "detected_packages"
        case deviceClean = "device_clean"
        case sdkStatus = "sdk_status"
        case blockReason = "block_reason"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case batteryLevel = "battery_level"
        case isCharging = "is_charging"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            device.deviceId ?? "",
            forKey: .deviceId
        )
        try container.encode(
            device.bundleId,
            forKey: .bundleId
        )
        try container.encode(
            device.hasSim,
            forKey: .hasSim
        )
        try container.encode(
            device.simCountry?.uppercased() ?? "",
            forKey: .simCountry
        )
        try container.encode(
            detectedPackages,
            forKey: .detectedPackages
        )
        try container.encode(
            deviceClean,
            forKey: .deviceClean
        )
        try container.encode(
            sdkStatus,
            forKey: .sdkStatus
        )
        try container.encode(
            blockReason,
            forKey: .blockReason
        )
        try container.encode(
            device.deviceModel,
            forKey: .deviceModel
        )
        try container.encode(
            "\(device.osName) \(device.osVersion)",
            forKey: .osVersion
        )
        try container.encode(
            batteryLevel,
            forKey: .batteryLevel
        )
        try container.encode(
            isCharging,
            forKey: .isCharging
        )
    }

    private var detectedPackages: String {
        var values = device.suspiciousApps

        if device.isJailbroken {
            values.append("root:jailbreak")
        }

        if device.isSimulator {
            values.append("simulator")
        }

        return values.joined(separator: ",")
    }

    private var deviceClean: Bool {
        !device.isJailbroken
            && !device.isSimulator
            && device.suspiciousApps.isEmpty
    }

    private var batteryLevel: Int {
        #if canImport(UIKit)
        let level = UIDevice.current.batteryLevel

        guard level >= 0 else {
            return 0
        }

        return min(
            100,
            max(0, Int((level * 100).rounded()))
        )
        #else
        return 0
        #endif
    }

    private var isCharging: Bool {
        #if canImport(UIKit)
        switch UIDevice.current.batteryState {
        case .charging,
             .full:
            return true

        case .unknown,
             .unplugged:
            return false

        @unknown default:
            return false
        }
        #else
        return false
        #endif
    }
}
