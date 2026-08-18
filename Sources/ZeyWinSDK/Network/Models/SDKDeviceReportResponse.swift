struct SDKDeviceReportResponse: Codable, Sendable {

    let sdkStatus: String
    let blockReason: String?

    enum CodingKeys: String, CodingKey {
        case sdkStatus = "sdk_status"
        case blockReason = "block_reason"
    }

    init(
        sdkStatus: String,
        blockReason: String? = nil
    ) {
        self.sdkStatus = sdkStatus
        self.blockReason = blockReason
    }
}
