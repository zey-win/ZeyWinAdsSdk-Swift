struct SDKEventRequest: Encodable, Sendable {

    let appId: String
    let apiKey: String
    let adId: String
    let adType: String?
    let eventType: String
    let deviceModel: String
    let osVersion: String
    let sdkVersion: String
    let deviceId: String?
    let bundleId: String

    init(
        apiKey: String,
        device: DeviceInfo,
        adId: String,
        adType: String?,
        eventType: String
    ) {
        self.appId = device.bundleId
        self.apiKey = apiKey
        self.adId = adId
        self.adType = adType
        self.eventType = eventType
        self.deviceModel = device.deviceModel
        self.osVersion = "\(device.osName) \(device.osVersion)"
        self.sdkVersion = SDKInitRequest.sdkVersion
        self.deviceId = device.deviceId
        self.bundleId = device.bundleId
    }

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case apiKey = "api_key"
        case adId = "ad_id"
        case adType = "ad_type"
        case eventType = "event_type"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case sdkVersion = "sdk_version"
        case deviceId = "device_id"
        case bundleId = "bundle_id"
    }
}
