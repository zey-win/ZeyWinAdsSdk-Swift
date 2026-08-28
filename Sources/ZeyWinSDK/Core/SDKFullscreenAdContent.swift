import Foundation

public struct SDKFullscreenAdContent: Equatable {
    public let mediaURL: URL
    public let targetURL: URL?
    public let durationSec: Int?
    public let skipAfterSec: Int?
    let tracking: SDKAdTracking?

    public init(
        mediaURL: URL,
        targetURL: URL? = nil,
        durationSec: Int? = nil,
        skipAfterSec: Int? = nil,
        tracking: SDKAdTracking? = nil
    ) {
        self.mediaURL = mediaURL
        self.targetURL = targetURL
        self.durationSec = durationSec
        self.skipAfterSec = skipAfterSec
        self.tracking = tracking
    }
}
