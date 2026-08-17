public struct SDKInitRequest: Codable, Sendable {

    public let apiKey: String
    public let device: DeviceInfo

    public init(
        apiKey: String,
        device: DeviceInfo
    ) {
        self.apiKey = apiKey
        self.device = device
    }
}
