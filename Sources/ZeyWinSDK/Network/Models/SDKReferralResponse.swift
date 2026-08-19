import Foundation

struct SDKReferralResponse: Decodable, Sendable {
    let hasReferral: Bool
    let offerURL: String?
    let clickId: String?

    enum CodingKeys: String, CodingKey {
        case hasReferral = "has_referral"
        case offerURL = "offer_url"
        case clickId = "click_id"
    }
}
