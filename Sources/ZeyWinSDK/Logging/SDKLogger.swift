enum SDKLogger {

    static var isEnabled = true

    static func log(
        _ message: String
    ) {
        guard isEnabled else {
            return
        }

        print("[ZeyWinSDK] \(message)")
    }
}
