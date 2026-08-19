import Foundation

struct SDKReferralCheckRequest: Encodable, Sendable {
    let apiKey: String
    let bundleId: String
    let deviceId: String?
    let simCountry: String?

    init(
        apiKey: String,
        device: DeviceInfo
    ) {
        self.apiKey = apiKey
        self.bundleId = device.bundleId
        self.deviceId = device.deviceId
        self.simCountry = device.simCountry
    }

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case bundleId = "bundle_id"
        case deviceId = "device_id"
        case simCountry = "sim_country"
    }
}
