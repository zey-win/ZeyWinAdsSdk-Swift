import Foundation

public struct SDKFullscreenAdContent: Equatable {
    public let mediaURL: URL
    public let targetURL: URL?
    let tracking: SDKAdTracking?

    public init(
        mediaURL: URL,
        targetURL: URL? = nil,
        tracking: SDKAdTracking? = nil
    ) {
        self.mediaURL = mediaURL
        self.targetURL = targetURL
        self.tracking = tracking
    }
}
