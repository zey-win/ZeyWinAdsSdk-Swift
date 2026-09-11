import XCTest
@testable import ZeyWinSDK

final class PromotionURLPersistenceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: PromotionURLStore!

    private let scope = PromotionURLScope(
        bundleIdentifier: "com.example.application",
        apiKey: "test-api-key"
    )

    override func setUp() {
        super.setUp()

        suiteName = "PromotionURLPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = PromotionURLStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil

        super.tearDown()
    }

    func testStoredOnFirstReceipt() throws {
        let original = "https://example.com/original"
        let resolver = ContentResolver(
            promotionURLStore: store
        )

        let action = try resolver.resolve(
            response: offerResponse(original),
            promotionScope: scope
        )

        XCTAssertEqual(action, .offer(try XCTUnwrap(URL(string: original))))
        XCTAssertEqual(
            defaults.string(forKey: store.primaryKey(for: scope)),
            original
        )
        XCTAssertEqual(
            defaults.string(forKey: store.backupKey(for: scope)),
            original
        )
    }

    func testNotOverwrittenByLaterServerUrl() throws {
        let original = "https://example.com/original"
        let later = "https://example.com/later"
        let resolver = ContentResolver(
            promotionURLStore: store
        )

        _ = try resolver.resolve(
            response: offerResponse(original),
            promotionScope: scope
        )
        _ = try resolver.resolve(
            response: offerResponse(later),
            promotionScope: scope
        )

        XCTAssertEqual(store.storedURL(for: scope)?.absoluteString, original)
        XCTAssertEqual(
            defaults.string(forKey: store.primaryKey(for: scope)),
            original
        )
        XCTAssertEqual(
            defaults.string(forKey: store.backupKey(for: scope)),
            original
        )
    }

    func testPersistIsWriteOnce() {
        let original = "https://example.com/original"
        let later = "https://example.com/later"

        let firstResult = store.resolve(
            candidate: original,
            for: scope
        )
        let secondResult = store.resolve(
            candidate: later,
            for: scope
        )

        XCTAssertEqual(firstResult?.absoluteString, original)
        XCTAssertEqual(secondResult?.absoluteString, original)
        XCTAssertEqual(store.storedURL(for: scope)?.absoluteString, original)
    }

    func testSurvivesRestart() {
        let original = "https://example.com/original"

        _ = store.resolve(candidate: original, for: scope)

        let restartedStore = PromotionURLStore(defaults: defaults)

        XCTAssertEqual(
            restartedStore.storedURL(for: scope)?.absoluteString,
            original
        )
    }

    func testHealsFromBackup() {
        let original = "https://example.com/original"
        let primaryKey = store.primaryKey(for: scope)

        _ = store.resolve(candidate: original, for: scope)
        defaults.removeObject(forKey: primaryKey)

        var restartedStore = PromotionURLStore(defaults: defaults)

        XCTAssertEqual(
            restartedStore.storedURL(for: scope)?.absoluteString,
            original
        )
        XCTAssertEqual(defaults.string(forKey: primaryKey), original)

        defaults.set("not a URL", forKey: primaryKey)
        restartedStore = PromotionURLStore(defaults: defaults)

        XCTAssertEqual(
            restartedStore.storedURL(for: scope)?.absoluteString,
            original
        )
        XCTAssertEqual(defaults.string(forKey: primaryKey), original)
    }

    func testFirstValidUrlWinsAfterNonUrl() throws {
        let original = "https://example.com/original"
        let resolver = ContentResolver(
            promotionURLStore: store
        )

        XCTAssertThrowsError(
            try resolver.resolve(
                response: offerResponse("not a URL"),
                promotionScope: scope
            )
        ) { error in
            guard
                let sdkError = error as? SDKError,
                case .invalidURL = sdkError
            else {
                return XCTFail("Expected SDKError.invalidURL, got \(error)")
            }
        }

        XCTAssertNil(store.storedURL(for: scope))
        XCTAssertNil(store.resolve(candidate: "ftp://example.com/offer", for: scope))

        let action = try resolver.resolve(
            response: offerResponse(original),
            promotionScope: scope
        )

        XCTAssertEqual(action, .offer(try XCTUnwrap(URL(string: original))))
        XCTAssertEqual(store.storedURL(for: scope)?.absoluteString, original)
    }

    func testResolvedPromotionKeepsOriginal() throws {
        let original = "https://example.com/original"
        let later = "https://example.com/later"
        let resolver = ContentResolver(
            promotionURLStore: store
        )

        _ = try resolver.resolve(
            response: offerResponse(original),
            promotionScope: scope
        )
        let resolvedAction = try resolver.resolve(
            response: offerResponse(later),
            promotionScope: scope
        )

        XCTAssertEqual(
            resolvedAction,
            .offer(try XCTUnwrap(URL(string: original)))
        )
    }

    func testReferralAndForceOfferShareWriteOnceScope() throws {
        let referralURL = "https://example.com/referral"
        let forceOfferURL = "https://example.com/force"

        _ = store.resolve(
            candidate: referralURL,
            for: scope
        )

        let resolver = ContentResolver(
            promotionURLStore: store
        )
        let forceOfferAction = try resolver.resolve(
            response: offerResponse(forceOfferURL),
            promotionScope: scope
        )

        XCTAssertEqual(
            forceOfferAction,
            .offer(try XCTUnwrap(URL(string: referralURL)))
        )
    }

    func testStorageIsScopedByBundleIdentifierAndAPIKey() {
        let firstScope = scope
        let otherBundleScope = PromotionURLScope(
            bundleIdentifier: "com.example.other",
            apiKey: scope.apiKey
        )
        let otherAPIKeyScope = PromotionURLScope(
            bundleIdentifier: scope.bundleIdentifier,
            apiKey: "other-api-key"
        )

        XCTAssertEqual(
            store.resolve(
                candidate: "https://example.com/first",
                for: firstScope
            )?.absoluteString,
            "https://example.com/first"
        )
        XCTAssertEqual(
            store.resolve(
                candidate: "https://example.com/other-bundle",
                for: otherBundleScope
            )?.absoluteString,
            "https://example.com/other-bundle"
        )
        XCTAssertEqual(
            store.resolve(
                candidate: "https://example.com/other-api-key",
                for: otherAPIKeyScope
            )?.absoluteString,
            "https://example.com/other-api-key"
        )
    }

    func testScopeKeysUseStableHashWithoutRawAPIKey() {
        let hashedStore = PromotionURLStore(
            defaults: defaults,
            keyPrefix: "test"
        )

        let primaryKey = hashedStore.primaryKey(for: scope)
        let restartedKey = PromotionURLStore(
            defaults: defaults,
            keyPrefix: "test"
        ).primaryKey(for: scope)
        let components = primaryKey.split(separator: ".")

        XCTAssertEqual(primaryKey, restartedKey)
        XCTAssertFalse(primaryKey.contains(scope.apiKey))
        XCTAssertEqual(components.count, 3)
        XCTAssertEqual(components[0], "test")
        XCTAssertEqual(components[2], "primary")
        XCTAssertEqual(components[1].count, 64)
        XCTAssertTrue(
            components[1].allSatisfy { $0.isHexDigit }
        )
    }

    private func offerResponse(
        _ url: String
    ) -> SDKInitResponse {
        SDKInitResponse(
            action: "offer",
            url: url
        )
    }
}
