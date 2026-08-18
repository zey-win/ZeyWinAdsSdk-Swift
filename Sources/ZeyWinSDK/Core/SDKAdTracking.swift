import Foundation

public struct SDKAdTracking: Equatable, Sendable {
    public let adId: String?
    public let adType: String?
    public let impressionURL: URL?
    public let clickURL: URL?
    public let completeURL: URL?
    public let rewardURL: URL?

    public init(
        adId: String? = nil,
        adType: String? = nil,
        impressionURL: URL? = nil,
        clickURL: URL? = nil,
        completeURL: URL? = nil,
        rewardURL: URL? = nil
    ) {
        self.adId = adId
        self.adType = adType
        self.impressionURL = impressionURL
        self.clickURL = clickURL
        self.completeURL = completeURL
        self.rewardURL = rewardURL
    }

    public var isEmpty: Bool {
        impressionURL == nil
            && clickURL == nil
            && completeURL == nil
            && rewardURL == nil
    }
}
