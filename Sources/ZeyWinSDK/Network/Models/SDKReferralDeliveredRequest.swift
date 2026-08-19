import Foundation

struct SDKReferralDeliveredRequest: Encodable, Sendable {
    let apiKey: String
    let bundleId: String
    let deviceId: String?
    let clickId: String?

    init(
        apiKey: String,
        device: DeviceInfo,
        clickId: String?
    ) {
        self.apiKey = apiKey
        self.bundleId = device.bundleId
        self.deviceId = device.deviceId
        self.clickId = clickId
    }

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case bundleId = "bundle_id"
        case deviceId = "device_id"
        case clickId = "click_id"
    }
}
