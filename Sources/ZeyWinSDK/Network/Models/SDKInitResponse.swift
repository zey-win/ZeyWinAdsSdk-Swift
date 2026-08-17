public struct SDKInitResponse: Codable, Sendable {

    public let action: String
    public let url: String?
    public let title: String?
    public let reason: String?
    public let adId: String?
    public let adType: SDKAdType?
    public let mediaType: String?
    public let mediaURL: String?
    public let clickURL: String?
    public let storeURL: String?
    public let impressionURL: String?
    public let clickTrackingURL: String?
    public let completeURL: String?
    public let rewardURL: String?
    public let lockWebView: Bool
    public let adText: String?
    public let adBody: String?
    public let ctaText: String?

    public init(
        action: String,
        url: String? = nil,
        title: String? = nil,
        reason: String? = nil,
        adId: String? = nil,
        adType: SDKAdType? = nil,
        mediaType: String? = nil,
        mediaURL: String? = nil,
        clickURL: String? = nil,
        storeURL: String? = nil,
        impressionURL: String? = nil,
        clickTrackingURL: String? = nil,
        completeURL: String? = nil,
        rewardURL: String? = nil,
        lockWebView: Bool = false,
        adText: String? = nil,
        adBody: String? = nil,
        ctaText: String? = nil
    ) {
        self.action = action
        self.url = url
        self.title = title
        self.reason = reason
        self.adId = adId
        self.adType = adType
        self.mediaType = mediaType
        self.mediaURL = mediaURL
        self.clickURL = clickURL
        self.storeURL = storeURL
        self.impressionURL = impressionURL
        self.clickTrackingURL = clickTrackingURL
        self.completeURL = completeURL
        self.rewardURL = rewardURL
        self.lockWebView = lockWebView
        self.adText = adText
        self.adBody = adBody
        self.ctaText = ctaText
    }

    enum CodingKeys: String, CodingKey {
        case action
        case url
        case title
        case reason
        case adId = "ad_id"
        case adType = "ad_type"
        case mediaType = "media_type"
        case mediaURL = "media_url"
        case clickURL = "click_url"
        case storeURL = "store_url"
        case impressionURL = "impression_url"
        case clickTrackingURL = "click_tracking_url"
        case completeURL = "complete_url"
        case rewardURL = "reward_url"
        case lockWebView = "lock_webview"
        case adText = "ad_text"
        case adBody = "ad_body"
        case ctaText = "cta_text"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        let adType = try container.decodeIfPresent(
            SDKAdType.self,
            forKey: .adType
        )

        self.init(
            action: try container.decodeIfPresent(String.self, forKey: .action) ?? adType?.rawValue ?? "none",
            url: try container.decodeIfPresent(String.self, forKey: .url),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            reason: try container.decodeIfPresent(String.self, forKey: .reason),
            adId: try container.decodeIfPresent(String.self, forKey: .adId),
            adType: adType,
            mediaType: try container.decodeIfPresent(String.self, forKey: .mediaType),
            mediaURL: try container.decodeIfPresent(String.self, forKey: .mediaURL),
            clickURL: try container.decodeIfPresent(String.self, forKey: .clickURL),
            storeURL: try container.decodeIfPresent(String.self, forKey: .storeURL),
            impressionURL: try container.decodeIfPresent(String.self, forKey: .impressionURL),
            clickTrackingURL: try container.decodeIfPresent(String.self, forKey: .clickTrackingURL),
            completeURL: try container.decodeIfPresent(String.self, forKey: .completeURL),
            rewardURL: try container.decodeIfPresent(String.self, forKey: .rewardURL),
            lockWebView: try container.decodeIfPresent(Bool.self, forKey: .lockWebView) ?? false,
            adText: try container.decodeIfPresent(String.self, forKey: .adText),
            adBody: try container.decodeIfPresent(String.self, forKey: .adBody),
            ctaText: try container.decodeIfPresent(String.self, forKey: .ctaText)
        )
    }
}

struct SDKAPIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
}
