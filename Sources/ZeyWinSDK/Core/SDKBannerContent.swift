import Foundation

public struct SDKBannerContent: Equatable, Sendable {
    public let title: String
    public let body: String?
    public let iconURL: URL?
    public let mediaURL: URL?
    public let targetURL: URL
    public let ctaText: String
    public let secondaryCTAText: String?
    public let popupDelaySec: Int?
    public let popupRepeatSec: Int?
    let tracking: SDKAdTracking?

    public init(
        title: String,
        body: String? = nil,
        iconURL: URL? = nil,
        mediaURL: URL? = nil,
        targetURL: URL,
        ctaText: String = "Open",
        secondaryCTAText: String? = nil,
        popupDelaySec: Int? = nil,
        popupRepeatSec: Int? = nil,
        tracking: SDKAdTracking? = nil
    ) {
        self.title = title
        self.body = body
        self.iconURL = iconURL
        self.mediaURL = mediaURL
        self.targetURL = targetURL
        self.ctaText = ctaText
        self.secondaryCTAText = secondaryCTAText
        self.popupDelaySec = popupDelaySec
        self.popupRepeatSec = popupRepeatSec
        self.tracking = tracking
    }
}
