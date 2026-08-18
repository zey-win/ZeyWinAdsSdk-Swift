import UIKit
import CoreTelephony

final class DeviceInfoProvider: DeviceInfoProviding {

    private let suspiciousURLSchemes = [
        "cydia",
        "sileo",
        "zbra",
        "filza",
        "activator",
        "undecimus",
        "newterm",
        "icleaner"
    ]

    private let jailbreakPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Applications/Zebra.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt"
    ]

    func collect() -> DeviceInfo {
        let bundle = Bundle.main
        let device = UIDevice.current
        let simCountries = collectSIMCountries()

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
            hasSim: !simCountries.isEmpty,
            simCountry: simCountries.first,
            isSimulator: isRunningOnSimulator,
            isJailbroken: isJailbroken,
            isSandboxReceipt: isSandboxReceipt,
            suspiciousApps: collectSuspiciousApps()
        )
    }

    private func collectSIMCountries() -> [String] {
        let networkInfo = CTTelephonyNetworkInfo()

        if let providers = networkInfo.serviceSubscriberCellularProviders {
            return Array(
                Set(
                    providers.values.compactMap {
                        $0.isoCountryCode?.uppercased()
                    }
                )
            ).sorted()
        }

        return []
    }

    private var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var isSandboxReceipt: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let fileManager = FileManager.default

        if jailbreakPaths.contains(where: fileManager.fileExists) {
            return true
        }

        let testPath = "/private/\(UUID().uuidString)"

        do {
            try "test".write(
                toFile: testPath,
                atomically: true,
                encoding: .utf8
            )
            try? fileManager.removeItem(
                atPath: testPath
            )
            return true
        } catch {
            return false
        }
        #endif
    }

    private func collectSuspiciousApps() -> [String] {
        suspiciousURLSchemes.filter { scheme in
            guard let url = URL(string: "\(scheme)://") else {
                return false
            }

            return UIApplication.shared.canOpenURL(url)
        }
    }
}
