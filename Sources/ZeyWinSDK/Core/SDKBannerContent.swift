import Foundation

public struct SDKBannerContent: Equatable {
    public let title: String
    public let targetURL: URL

    public init(
        title: String,
        targetURL: URL
    ) {
        self.title = title
        self.targetURL = targetURL
    }
}
