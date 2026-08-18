import Foundation

public struct SDKBannerContent: Equatable {
    public let title: String
    public let body: String?
    public let mediaURL: URL?
    public let targetURL: URL
    public let ctaText: String
    let tracking: SDKAdTracking?

    public init(
        title: String,
        body: String? = nil,
        mediaURL: URL? = nil,
        targetURL: URL,
        ctaText: String = "Open",
        tracking: SDKAdTracking? = nil
    ) {
        self.title = title
        self.body = body
        self.mediaURL = mediaURL
        self.targetURL = targetURL
        self.ctaText = ctaText
        self.tracking = tracking
    }
}
