import Foundation

public enum SDKAction: Equatable {

    case offer(URL)
    case internalAd(SDKFullscreenAdContent)
    case banner(SDKBannerContent)
    case blocked(reason: String?)
    case none
}

extension SDKAction: CustomStringConvertible {

    public var description: String {
        switch self {
        case .offer(let url):
            return "offer(\(url.absoluteString))"

        case .internalAd(let content):
            return "internalAd(media: \(content.mediaURL.absoluteString), target: \(content.targetURL?.absoluteString ?? "nil"))"

        case .banner(let banner):
            return "banner(title: \(banner.title), target: \(banner.targetURL.absoluteString))"

        case .blocked(let reason):
            return "blocked(\(reason ?? "unknown"))"

        case .none:
            return "none"
        }
    }
}
