import Foundation

public struct SDKInitRequest: Codable, Sendable {

    public static let sdkVersion = "3.9.55-swift"

    public let apiKey: String
    public let device: DeviceInfo
    public let adType: SDKAdType

    public init(
        apiKey: String,
        device: DeviceInfo,
        adType: SDKAdType = .interstitial
    ) {
        self.apiKey = apiKey
        self.device = device
        self.adType = adType
    }

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case apiKey = "api_key"
        case adType = "ad_type"
        case country
        case language
        case platform
        case deviceType = "device_type"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case sdkVersion = "sdk_version"
        case deviceId = "device_id"
        case appVersion = "app_version"
        case hasSim = "has_sim"
        case simCountry = "sim_country"
        case isSimulator = "is_simulator"
        case isJailbroken = "is_jailbroken"
        case isSandboxReceipt = "is_sandbox_receipt"
        case suspiciousApps = "suspicious_apps"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        let bundleId = try container.decode(
            String.self,
            forKey: .bundleId
        )
        let appVersion = try container.decodeIfPresent(
            String.self,
            forKey: .appVersion
        ) ?? "unknown"

        let device = DeviceInfo(
            bundleId: bundleId,
            appVersion: appVersion,
            deviceModel: try container.decodeIfPresent(String.self, forKey: .deviceModel) ?? "unknown",
            osName: "iOS",
            osVersion: try container.decodeIfPresent(String.self, forKey: .osVersion) ?? "unknown",
            locale: try container.decodeIfPresent(String.self, forKey: .language) ?? "en",
            timezone: TimeZone.current.identifier,
            language: try container.decodeIfPresent(String.self, forKey: .language) ?? "en",
            country: try container.decodeIfPresent(String.self, forKey: .country),
            platform: try container.decodeIfPresent(String.self, forKey: .platform) ?? "ios",
            deviceType: try container.decodeIfPresent(String.self, forKey: .deviceType) ?? "phone",
            deviceId: try container.decodeIfPresent(String.self, forKey: .deviceId),
            hasSim: try container.decodeIfPresent(Bool.self, forKey: .hasSim) ?? false,
            simCountry: try container.decodeIfPresent(String.self, forKey: .simCountry),
            isSimulator: try container.decodeIfPresent(Bool.self, forKey: .isSimulator) ?? false,
            isJailbroken: try container.decodeIfPresent(Bool.self, forKey: .isJailbroken) ?? false,
            isSandboxReceipt: try container.decodeIfPresent(Bool.self, forKey: .isSandboxReceipt) ?? false,
            suspiciousApps: try container.decodeIfPresent([String].self, forKey: .suspiciousApps) ?? []
        )

        self.init(
            apiKey: try container.decode(String.self, forKey: .apiKey),
            device: device,
            adType: try container.decodeIfPresent(SDKAdType.self, forKey: .adType) ?? .interstitial
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            device.bundleId,
            forKey: .bundleId
        )
        try container.encode(
            apiKey,
            forKey: .apiKey
        )
        try container.encode(
            adType.rawValue,
            forKey: .adType
        )
        try container.encodeIfPresent(
            device.country,
            forKey: .country
        )
        try container.encode(
            device.language,
            forKey: .language
        )
        try container.encode(
            device.platform,
            forKey: .platform
        )
        try container.encode(
            device.deviceType,
            forKey: .deviceType
        )
        try container.encode(
            device.deviceModel,
            forKey: .deviceModel
        )
        try container.encode(
            device.osVersion,
            forKey: .osVersion
        )
        try container.encode(
            Self.sdkVersion,
            forKey: .sdkVersion
        )
        try container.encodeIfPresent(
            device.deviceId,
            forKey: .deviceId
        )
        try container.encode(
            device.appVersion,
            forKey: .appVersion
        )
        try container.encode(
            device.hasSim,
            forKey: .hasSim
        )
        try container.encodeIfPresent(
            device.simCountry,
            forKey: .simCountry
        )
        try container.encode(
            device.isSimulator,
            forKey: .isSimulator
        )
        try container.encode(
            device.isJailbroken,
            forKey: .isJailbroken
        )
        try container.encode(
            device.isSandboxReceipt,
            forKey: .isSandboxReceipt
        )
        try container.encode(
            device.suspiciousApps,
            forKey: .suspiciousApps
        )
    }
}
