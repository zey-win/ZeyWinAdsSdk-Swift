import Foundation

public struct DeviceInfo: Codable, Equatable, Sendable {

    public let bundleId: String
    public let appVersion: String
    public let deviceModel: String
    public let osName: String
    public let osVersion: String
    public let locale: String
    public let timezone: String

    public init(
        bundleId: String,
        appVersion: String,
        deviceModel: String,
        osName: String,
        osVersion: String,
        locale: String,
        timezone: String
    ) {
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.osName = osName
        self.osVersion = osVersion
        self.locale = locale
        self.timezone = timezone
    }
}
