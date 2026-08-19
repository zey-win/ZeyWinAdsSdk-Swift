struct SDKWebViewEventRequest: Encodable, Sendable {

    let apiKey: String
    let bundleId: String
    let deviceId: String?
    let adId: String
    let adType: String?
    let status: String
    let failReason: String?

    init(
        apiKey: String,
        device: DeviceInfo,
        adId: String,
        adType: String?,
        status: String,
        failReason: String? = nil
    ) {
        self.apiKey = apiKey
        self.bundleId = device.bundleId
        self.deviceId = device.deviceId
        self.adId = adId
        self.adType = adType
        self.status = status
        self.failReason = failReason
    }

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case bundleId = "bundle_id"
        case deviceId = "device_id"
        case adId = "ad_id"
        case adType = "ad_type"
        case status
        case failReason = "fail_reason"
    }
}
