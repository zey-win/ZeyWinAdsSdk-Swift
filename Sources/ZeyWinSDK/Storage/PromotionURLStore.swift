import CryptoKit
import Foundation

struct PromotionURLScope: Equatable, Sendable {
    let bundleIdentifier: String
    let apiKey: String
}

final class PromotionURLStore {

    private static let lock = NSLock()

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "com.zeywin.sdk.promotion-url"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func resolve(
        candidate: String?,
        for scope: PromotionURLScope
    ) -> URL? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        if let storedURL = readStoredURL(for: scope) {
            return storedURL
        }

        guard let candidateURL = Self.validURL(candidate) else {
            return nil
        }

        let value = candidateURL.absoluteString

        // Write the backup first so an interrupted write can heal primary.
        defaults.set(value, forKey: backupKey(for: scope))
        defaults.set(value, forKey: primaryKey(for: scope))

        return candidateURL
    }

    func storedURL(
        for scope: PromotionURLScope
    ) -> URL? {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        return readStoredURL(for: scope)
    }

    func primaryKey(
        for scope: PromotionURLScope
    ) -> String {
        "\(keyPrefix).\(encodedScope(scope)).primary"
    }

    func backupKey(
        for scope: PromotionURLScope
    ) -> String {
        "\(keyPrefix).\(encodedScope(scope)).backup"
    }

    private func readStoredURL(
        for scope: PromotionURLScope
    ) -> URL? {
        let primaryKey = primaryKey(for: scope)
        let backupKey = backupKey(for: scope)

        if let primaryURL = Self.validURL(
            defaults.string(forKey: primaryKey)
        ) {
            let value = primaryURL.absoluteString

            if defaults.string(forKey: backupKey) != value {
                defaults.set(value, forKey: backupKey)
            }

            return primaryURL
        }

        if let backupURL = Self.validURL(
            defaults.string(forKey: backupKey)
        ) {
            defaults.set(
                backupURL.absoluteString,
                forKey: primaryKey
            )

            return backupURL
        }

        return nil
    }

    private func encodedScope(
        _ scope: PromotionURLScope
    ) -> String {
        let value = "\(scope.bundleIdentifier.utf8.count):\(scope.bundleIdentifier)\(scope.apiKey.utf8.count):\(scope.apiKey)"

        return SHA256.hash(
            data: Data(value.utf8)
        ).map { String(format: "%02x", $0) }.joined()
    }

    static func validURL(
        _ value: String?
    ) -> URL? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard
            let url = URL(string: trimmedValue),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host,
            !host.isEmpty
        else {
            return nil
        }

        return url
    }
}
