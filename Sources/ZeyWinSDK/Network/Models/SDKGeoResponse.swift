struct SDKGeoResponse: Decodable, Sendable {

    let country: String?

    enum CodingKeys: String, CodingKey {
        case country
        case countryCode = "country_code"
        case countryCodeISO = "countryCode"
    }

    init(
        country: String?
    ) {
        self.country = country
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        let value = try container.decodeIfPresent(
            String.self,
            forKey: .country
        ) ?? container.decodeIfPresent(
            String.self,
            forKey: .countryCode
        ) ?? container.decodeIfPresent(
            String.self,
            forKey: .countryCodeISO
        )

        country = value?.uppercased()
    }
}
