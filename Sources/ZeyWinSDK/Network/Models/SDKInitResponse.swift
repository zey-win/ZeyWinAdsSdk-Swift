public struct SDKInitResponse: Codable, Sendable {

    public let action: String
    public let url: String?
    public let title: String?
    public let reason: String?

    public init(
        action: String,
        url: String? = nil,
        title: String? = nil,
        reason: String? = nil
    ) {
        self.action = action
        self.url = url
        self.title = title
        self.reason = reason
    }
}
