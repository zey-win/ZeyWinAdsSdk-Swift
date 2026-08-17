import Foundation

public enum SDKAction: Equatable {

    case offer(URL)
    case internalAd(URL)
    case banner(SDKBannerContent)
    case blocked(reason: String?)
    case none
}

extension SDKAction: CustomStringConvertible {

    public var description: String {
        switch self {
        case .offer(let url):
            return "offer(\(url.absoluteString))"

        case .internalAd(let url):
            return "internalAd(\(url.absoluteString))"

        case .banner(let banner):
            return "banner(title: \(banner.title), target: \(banner.targetURL.absoluteString))"

        case .blocked(let reason):
            return "blocked(\(reason ?? "unknown"))"

        case .none:
            return "none"
        }
    }
}
