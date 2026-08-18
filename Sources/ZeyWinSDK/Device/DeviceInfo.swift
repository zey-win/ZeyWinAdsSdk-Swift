import Foundation

public struct DeviceInfo: Codable, Equatable, Sendable {

    public let bundleId: String
    public let appVersion: String
    public let deviceModel: String
    public let osName: String
    public let osVersion: String
    public let locale: String
    public let timezone: String
    public let language: String
    public let country: String?
    public let platform: String
    public let deviceType: String
    public let deviceId: String?
    public let hasSim: Bool
    public let simCountry: String?
    public let isSimulator: Bool
    public let isJailbroken: Bool
    public let isSandboxReceipt: Bool
    public let suspiciousApps: [String]

    public init(
        bundleId: String,
        appVersion: String,
        deviceModel: String,
        osName: String,
        osVersion: String,
        locale: String,
        timezone: String,
        language: String = Locale.current.languageCode ?? "en",
        country: String? = Locale.current.regionCode,
        platform: String = "ios",
        deviceType: String = "phone",
        deviceId: String? = nil,
        hasSim: Bool = false,
        simCountry: String? = nil,
        isSimulator: Bool = false,
        isJailbroken: Bool = false,
        isSandboxReceipt: Bool = false,
        suspiciousApps: [String] = []
    ) {
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.osName = osName
        self.osVersion = osVersion
        self.locale = locale
        self.timezone = timezone
        self.language = language
        self.country = country
        self.platform = platform
        self.deviceType = deviceType
        self.deviceId = deviceId
        self.hasSim = hasSim
        self.simCountry = simCountry
        self.isSimulator = isSimulator
        self.isJailbroken = isJailbroken
        self.isSandboxReceipt = isSandboxReceipt
        self.suspiciousApps = suspiciousApps
    }
}
