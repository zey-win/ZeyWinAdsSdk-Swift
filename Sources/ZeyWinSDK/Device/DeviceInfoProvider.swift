import UIKit

final class DeviceInfoProvider: DeviceInfoProviding {

    func collect() -> DeviceInfo {
        let bundle = Bundle.main
        let device = UIDevice.current

        return DeviceInfo(
            bundleId: bundle.bundleIdentifier ?? "unknown",
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            deviceModel: device.model,
            osName: device.systemName,
            osVersion: device.systemVersion,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            language: Locale.current.languageCode ?? "en",
            country: Locale.current.regionCode,
            platform: "ios",
            deviceType: UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone",
            deviceId: device.identifierForVendor?.uuidString,
            hasSim: false,
            simCountry: nil
        )
    }
}
