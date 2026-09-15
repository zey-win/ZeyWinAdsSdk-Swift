# Unity → Swift semantic parity analysis — 6.2 (rerun on `tests/ios-sdk-coverage`)

## Scope and evidence

- Unity baseline: `4d3e5800e85acb2394b797ffa7a38f9794c97586`
- Unity current `main`: `a7ade59de00990ceab16c6b527d6c727e4233f6e`
- Analysed range: `4d3e580..a7ade59`
- Swift source of truth: current branch `tests/ios-sdk-coverage`
- Detector input read: `/tmp/unity-swift-example-report.md` (the report-only output for
  this exact range).
- Primary evidence: the real Unity git diff and commits `29a8a04`, `9ecca65`, and
  `62e0a39`; current files in this Swift working tree.

This is a behaviour comparison, not a line-by-line port review. In particular, raw
JNI changes are not an iOS contract by themselves. No Swift production file, Unity
file, sync branch, PR, or `.sync/unity-last-synced-commit` was changed by this audit.

The previous version of this report was produced from a different Swift checkout. This
rerun treats `tests/ios-sdk-coverage` as the only source of truth. It includes
`Storage/PromotionURLStore.swift`, `PromotionURLPersistenceTests.swift`,
`SDKWebViewIntegrationTests.swift`, and `SDKDeviceE2ETests.swift`; all are counted as
coverage below.

## Status summary for the 10 Unity diff entities

| Status | Count | Items |
| --- | ---: | --- |
| `ALREADY_IMPLEMENTED` | 3 | HTML host-window selection; startup loader window; offer WebView surface/windowing |
| `PARTIALLY_IMPLEMENTED` | 0 | — |
| `MISSING_IN_SWIFT` | 0 | — |
| `NOT_APPLICABLE_TO_SWIFT` | 7 | theme bridge, Android JNI/device/referral/security/motion changes, Unity init delay, Unity version bump |
| `NEEDS_HUMAN_REVIEW` | 0 | — |

There is no proven API payload, response-decoding, referral, promotion-persistence,
media-configuration, or host-modal presentation parity regression in this range.

## Stage 6.3 targeted offer-presentation reproduction

- **Test host:** `TestHost/ZeyWinSDKTestHost.xcodeproj` contains a minimal UIKit app
  and app-hosted XCTest bundle. It depends on the local package at the repository
  root; it does not use a production backend.
- **Test added:**
  `HostedOfferPresentationTests.testOfferIsVisibleAboveExistingFullScreenHostModalAndDismissesCleanly`.
  It starts the real host app lifecycle, presents a full-screen host modal, then uses
  the real `ContentPresenter` to show an `.offer`. It asserts that
  `SDKWebViewController` is topmost, attached to the active scene and visible, closes
  through its callback, restores the host modal, and does not add an SDK `UIWindow`.
- **Simulator result:** the app-hosted test passed on iPhone 16 / iOS 18.5
  (1 executed, 0 failed, 0 skipped). This is a real UIKit window scene, not the
  hostless SwiftPM XCTest environment.
- **Production result:** the current worktree's `ContentPresenter` uses
  `topmostPresentationController(from:)` before presenting an offer. The hosted test
  verifies that minimal approach. No production source was edited as part of the
  hosted-test implementation; the already-present topmost-presenter change is the
  correct minimal resolution for the original host-modal risk. A dedicated offer
  `UIWindow` is not required.
- **Test-infrastructure result:** the local WebKit navigation probe ignores only the
  two representations WebKit uses for a superseded navigation:
  `NSURLErrorCancelled` and `WebKitErrorDomain` code `102` (interrupted frame load).
  All other navigation failures still fail the test. The targeted back-navigation
  test passed after this correction.
- **Verification:** the default `ZeyWinSDK` scheme passed on iPhone 16 / iOS 18.5
  with **59 executed, 0 failed, 3 skipped**. The skips are only the opt-in
  production-network WebView tests; the app-hosted test is run by its separate test
  host scheme.

## Delta from the previous 6.2 report

- The earlier report incorrectly treated this checkout as lacking
  `PromotionURLStore`, WebView integration tests, and device E2E tests. Those files
  are present on `tests/ios-sdk-coverage` and are now included in the evidence.
- The prior claim that no app-level referral presentation test existed is superseded
  by `testReferralOfferFlowsThroughLoaderPresentationAndDeliveryWithoutAutopresentation`.
- The prior claim that no WebView XCTest file existed is superseded by nine
  `SDKWebViewIntegrationTests`, including deterministic local WebKit checks and
  opt-in network checklist/redirect/ATS checks.
- The offer-window conclusion is now `ALREADY_IMPLEMENTED`: the app-hosted test
  proved the host-modal route and confirmed that topmost-presenter routing preserves
  the host modal without a dedicated SDK window.
- Promotion persistence is no longer a possible parity gap. It is explicitly
  write-once, primary/backup-healing, scope-isolated, and protected against automatic
  offer presentation without a new referral/offer signal.

## Current-branch reassessment of the requested flows

| Flow | Status | Current Swift evidence | Remaining boundary |
| --- | --- | --- | --- |
| Offer WebView presentation | `ALREADY_IMPLEMENTED` | `ContentPresenter` creates a fullscreen `SDKWebViewController` from the topmost active presenter. `SDKDeviceE2ETests.testContentPresenterRoutesOfferToWebViewWithOriginalURL` proves the ordinary URL route. The app-hosted `HostedOfferPresentationTests.testOfferIsVisibleAboveExistingFullScreenHostModalAndDismissesCleanly` proves visible presentation above a full-screen host modal, clean dismissal, restoration of the host modal, and no extra SDK window. | A distinct, host-owned second `UIWindow` or renderer surface is outside this reproduction and remains product/device QA rather than evidence for copying Unity's window architecture. |
| Loader window | `ALREADY_IMPLEMENTED` | `ContentPresenter.overlayView(...)` creates `SDKOverlayWindow`; `SDKDeviceE2ETests.testReferralOfferFlowsThroughLoaderPresentationAndDeliveryWithoutAutopresentation` verifies the start-flow loading → offer presentation ordering through a recording presenter. | No direct assertion currently inspects `UIWindow` lifetime/level with the real `ContentPresenter`; this is a coverage gap, not a proven implementation gap. |
| Referral flow | `ALREADY_IMPLEMENTED` | `ZeyWinSDK.resolveReferralIfNeeded(...)` calls `/referral/check`, persists/resolves the offer, presents it, and calls `/referral/delivered`. The device E2E test verifies loading, offer, delivery, and no presentation from stored state alone. `RealAPIClientTests` covers `/referral/check`, `/referral/check-by-click`, and `/referral/delivered` payload/response contracts. Banner/CTA preserves the backend click URL in `testBannerCTATapForwardsOriginalBackendClickURL`. | The SDK has no direct runtime call to `checkReferralByClick` in this path; the backend/redirect behaviour after the original click URL leaves the SDK boundary and needs backend/real-device integration evidence rather than a speculative Swift port. |
| Promotion URL persistence | `ALREADY_IMPLEMENTED` | `PromotionURLStore` validates HTTP(S), writes primary + backup once, heals primary from backup, uses a SHA-256 scope for bundle/API key, and is injected into both `ContentResolver` and referral resolution. Ten isolated `PromotionURLPersistenceTests` cover first write, write-once, restart, healing, invalid candidates, scope isolation, raw-key protection, and referral/force ordering. | Unity's broader `OfferAssignmentStore` can restore and lock a saved offer automatically; Swift intentionally does **not** auto-present without a new signal, and the device E2E test explicitly protects that Swift contract. |
| Device and security | `PARTIALLY_IMPLEMENTED` | `DeviceInfoProvider`, `makeDeviceReport`, and `SDKDeviceReportRequest` encode iOS device/security findings. API contract tests cover complete payload and blocked response; device E2E covers blocked fallback, blocked-without-creative, invalid referral, missing creative, network failure, and WebView load failure. | Tests use deterministic fixture device data; live CoreTelephony, IDFV, jailbreak/suspicious-scheme detection and physical device security behaviour cannot be asserted reliably in unit CI. |

## Per-change semantic comparison

### 1. HTML ad host-window lookup

- **Status:** `ALREADY_IMPLEMENTED`
- **Unity commit / file / symbol:** `29a8a04` —
  `Runtime/Plugins/iOS/ZeyWinAdsHtmlView.mm`, `_ZeyWinAds_ShowHtmlAd`.
- **Actual Unity behaviour change:** after the startup loader became a second
  `UIWindow`, `windowScene.windows.firstObject` could select the loader rather than
  the host app window. Unity now chooses `isKeyWindow` first and only then falls back
  to `firstObject`, so an HTML ad modal is presented from the actual app hierarchy.
- **Swift equivalent:** `ContentPresenter.presentWebView(...)` receives the host
  `UIViewController` explicitly and presents `SDKWebViewController` from it. It does
  not discover a scene window through `windows.firstObject`. The only Swift window
  discovery is `ContentPresenter.overlayView(...)`, which first uses
  `viewController.view.window?.windowScene`.
- **Difference / risk:** the Swift implementation reaches the same outcome by a
  safer architectural route: there is no first-window selection to corrupt. Risk is
  low. Copying Unity's key-window scan into Swift would add an unnecessary second
  source of truth.
- **Existing test coverage:** `ContentResolverTests.testUnityInterstitialResponseResolvesToInternalAd`
  covers resolution; `SDKDeviceE2ETests.testShowInterstitialPresentsInternalAdWithResolvedClickTarget`
  covers the internal-ad presentation boundary. Neither test creates a second SDK
  `UIWindow`, so multi-window host selection is still untested.
- **Recommended test:** simulator presentation test with an SDK overlay window
  present; assert the internal HTML/ad controller is still presented from the caller's
  app view controller.
- **Port required:** **No.**

### 2. Startup loader gets an independent window

- **Status:** `ALREADY_IMPLEMENTED`
- **Unity commit / file / symbol:** `29a8a04` —
  `Runtime/Plugins/iOS/ZeyWinAdsStartupOverlay.mm`,
  `ZeyWinAdsStartupOverlayCreateWindow`, `ZeyWinAdsStartupOverlayAttach`, and
  `ZeyWinAdsStartupOverlayHide`.
- **Actual Unity behaviour change:** the loading overlay moved from a sibling view in
  Unity's main window to its own `UIWindow` at `UIWindowLevelAlert + 1`. This removes
  a Unity Metal/GL same-window ordering race and hides/releases the overlay window on
  dismissal.
- **Swift equivalent:** `ContentPresenter.overlayView(...)` already creates an
  `SDKOverlayWindow` in the active `UIWindowScene`, installs an
  `SDKOverlayViewController`, and `presentLoading(...)` pins the loader to that
  independent window. `removeOverlayWindowIfEmpty()` hides and releases it.
- **Difference / risk:** Swift uses `.alert - 1`, not Unity's `.alert + 1`; that is
  intentionally below system alerts and does not weaken its ordering above the normal
  application window. It is a policy difference, not evidence of a bug. Risk is low
  for the Unity rendering race because a native Swift host does not use Unity's render
  surface.
- **Existing test coverage:** `SDKDeviceE2ETests.testReferralOfferFlowsThroughLoaderPresentationAndDeliveryWithoutAutopresentation`
  proves the mock-based start-flow order includes loading before the referral offer.
  No current XCTest directly inspects the real loader window's lifetime or level.
- **Recommended test:** iOS Simulator test that presents/dismisses the loader and
  verifies a distinct SDK window exists while loading and is released afterward. A
  notch/Dynamic Island visual check remains device/manual QA.
- **Port required:** **No.**

### 3. Dark-mode trait lookup

- **Status:** `NOT_APPLICABLE_TO_SWIFT`
- **Unity commit / file / symbol:** `29a8a04` —
  `Runtime/Plugins/iOS/ZeyWinAdsTheme.mm`, `_ZeyWinAds_IsDarkMode`.
- **Actual Unity behaviour change:** the C#/native bridge now reads traits from the
  key app window instead of an arbitrary first scene window after the loader adds its
  own window.
- **Swift equivalent:** there is no Swift `IsDarkMode` bridge, backend field, or
  public theme contract. `SDKLoadingViewController` and the presentation views own
  their UIKit appearance directly; no current request changes according to the
  system colour scheme.
- **Difference / risk:** this fixes a Unity-native bridge implementation detail,
  not a cross-SDK API behaviour. Adding a trait lookup to Swift would create unused
  functionality. Risk is low.
- **Existing / recommended tests:** none are required for this Unity delta. If Swift
  later gains a documented dynamic-theme feature, add a trait-collection UI test as
  part of that feature rather than as a sync port.
- **Port required:** **No.**

### 4. Offer WebView surface above the app

- **Status:** `ALREADY_IMPLEMENTED`
- **Unity commit / file / symbol:** `29a8a04` —
  `Runtime/Plugins/iOS/ZeyWinAdsWebView.mm`, `ZeyWinAdsWebViewHost.attach`,
  `createOfferWindowRelativeTo`, `bringToFront`, and `detach`.
- **Actual Unity behaviour change:** the offer `WKWebView` moved from a view inside
  the key window to a dedicated `UIWindow` at normal + 1. The change prevents Unity's
  renderer from flashing above the offer and keeps the offer visible after
  permission/system UI transitions. The same commit retains navigation, JavaScript,
  cookie, inline-playback, and external-scheme logic; it does not alter their
  contracts.
- **Swift equivalent:** `ContentPresenter.presentWebView(...)` resolves the topmost
  presented controller before it presents a fullscreen `SDKWebViewController`.
  `SDKWebViewController.makeWebViewConfiguration()` sets
  `allowsInlineMediaPlayback = true` and
  `mediaTypesRequiringUserActionForPlayback = []`. `setupWebView()` uses safe-area
  constraints, and `WKNavigationDelegate` keeps normal web navigation inside the
  controller. These cover the offer's normal full-screen and media behaviour.
- **Resolution:** the app-hosted integration test presents a real full-screen host
  modal, then verifies that the offer is topmost and visibly attached to the active
  scene. It closes the offer, confirms the host modal remains presented, and checks
  that the scene window count is unchanged. The minimal topmost-presenter route is
  sufficient for the UIKit modal case; Unity's dedicated offer window is unnecessary
  for this Swift SDK.
- **Risk:** low for this parity item. A separate host-owned `UIWindow`/rendering
  surface is still a different product scenario and should be device-tested if a host
  uses one.
- **Existing test coverage:** `ContentResolverTests.testOfferResponse` verifies the
  offer action; `RealAPIClientTests.testCheckReferralPostsPayloadAndDecodesOffer`
  verifies the referral contract; and
  `SDKDeviceE2ETests.testContentPresenterRoutesOfferToWebViewWithOriginalURL` proves
  the ordinary real presenter route. The app-hosted
  `HostedOfferPresentationTests.testOfferIsVisibleAboveExistingFullScreenHostModalAndDismissesCleanly`
  proves the host-modal route. The current
  `SDKWebViewIntegrationTests` additionally cover JavaScript, cookie persistence,
  session navigation, deep-link routing, history, safe-area/orientation, plus opt-in
  production checklist, redirect-chain, and ATS cases.
- **Port required:** **No additional port.** The minimal modal routing present in the
  current Swift source is verified; no dedicated offer window is needed.

### 5. Device identity JNI hardening

- **Status:** `NOT_APPLICABLE_TO_SWIFT`
- **Unity commit / file / symbol:** `9ecca65` —
  `Runtime/Core/DeviceIdentity.cs`, `GetFastDeviceId`, `GetSimCountry`, and
  `HasSim`.
- **Actual Unity behaviour change:** Android-only calls moved from reflective
  `AndroidJavaClass.CallStatic` to `AndroidJniSafe` raw JNI calls to avoid an ART
  cold-start abort. The Unity iOS `IDFA`/`IDFV` branch is unchanged.
- **Swift equivalent:** `DeviceInfoProvider.collect()` gets the identifier from
  `UIDevice.current.identifierForVendor`, SIM information from `CoreTelephony`, and
  encodes it through `SDKInitRequest` / `SDKDeviceReportRequest`. There is no JNI or
  Unity runtime on iOS to harden.
- **Difference / risk:** none caused by this delta. The SDKs use platform-native
  identity mechanisms by design. Risk is low.
- **Existing test coverage:** `RealAPIClientTests.testFetchInitialConfigurationPostsJSONAndDecodesResponse`,
  `testReportDevicePostsUnityCompatiblePayload`, and
  `testDeviceReportEncodesCompletePayloadAndDecodesBlockedState` exercise supplied
  device/security payloads. `SDKDeviceE2ETests` covers the resulting blocked and
  fallback decisions. They intentionally do not assert live `CoreTelephony`/IDFV
  values.
- **Recommended test:** no port test. A future `DeviceInfoProvider` test should use
  injected platform services rather than assert a live identifier or SIM state.
- **Port required:** **No.**

### 6. Unity SDK-version constant

- **Status:** `NOT_APPLICABLE_TO_SWIFT`
- **Unity commit / file / symbol:** `62e0a39` —
  `Runtime/Core/Models.cs`, `ZeyWinAdsConfig.SdkVersion`: `3.9.62` → `3.9.63`.
- **Actual Unity behaviour change:** only the Unity release/telemetry version value
  changed; no request/response schema changed.
- **Swift equivalent:** `SDKInitRequest.sdkVersion` is Swift-specific
  (`3.9.55-swift`) and is reused by `SDKEventRequest`.
- **Difference / risk:** the values differ, as SDK implementation versions should.
  This audit cannot establish a release-management rule requiring all SDKs to share a
  version number. Risk is low for compatibility, but telemetry needs an explicit
  owner if version currency is required.
- **Existing test coverage:** the ads request test encodes `sdk_version`; it does not
  need to equal Unity's version.
- **Recommended test:** none for this delta. If release policy requires a format or
  automatic bump, introduce that policy in the Swift release workflow, not via Unity
  sync.
- **Port required:** **No.**

### 7. Motion collection JNI hardening

- **Status:** `NOT_APPLICABLE_TO_SWIFT`
- **Unity commit / file / symbol:** `9ecca65` —
  `Runtime/Core/MotionCollector.cs`, `MotionCollector.Collect`.
- **Actual Unity behaviour change:** only the Android branch changes how it invokes
  `ZeyWinAdsMotionCollector`; the iOS native `_ZeyWinAds_CollectMotion` path and the
  `MotionData` payload shape are unchanged.
- **Swift equivalent:** this Swift SDK currently has no motion-collection model or
  request field. That is a pre-existing product-scope difference, not a behavioural
  change introduced by this Unity range.
- **Difference / risk:** no new Swift parity gap can be inferred. Adding motion
  collection would require a privacy/contract decision, not a transport port. Risk
  of automatic implementation is high.
- **Existing / recommended tests:** no Swift motion contract exists, so no test is
  required for this Android-only delta. If a backend contract later requires motion
  fields for iOS, add a consent-aware device-service interface and deterministic
  encoding tests as a separately approved feature.
- **Port required:** **No.**

### 8. Referral install-referrer call hardening

- **Status:** `NOT_APPLICABLE_TO_SWIFT`
- **Unity commit / file / symbol:** `9ecca65` —
  `Runtime/Core/ReferralManager.cs`, `TryInstallReferrer`.
- **Actual Unity behaviour change:** Android's Play Install Referrer invocation now
  uses raw JNI. The fallback device-id referral check remains the same, and the
  non-Android path is unchanged.
- **Swift equivalent:** `ZeyWinSDK.resolveReferralIfNeeded(...)` sends
  `SDKReferralCheckRequest` to `/referral/check`. `APIClientProtocol` also exposes
  `/referral/check-by-click` through `checkReferralByClick`, but raw Android Install
  Referrer has no iOS equivalent.
- **Difference / risk:** this is Android crash prevention, not a changed referral
  response contract. It supplies no evidence for changing the Swift referral flow.
  Risk is low for the delta.
- **Existing test coverage:** `RealAPIClientTests.testCheckReferralPostsPayloadAndDecodesOffer`
  and `testCheckReferralByClickPostsClickId` cover the HTTP contracts.
  `SDKDeviceE2ETests.testReferralOfferFlowsThroughLoaderPresentationAndDeliveryWithoutAutopresentation`
  drives the app-level `/referral/check` → offer → delivery flow, while
  `testInvalidReferralURLFallsBackWithoutPresentingOffer` covers invalid referral
  input.
- **Recommended test:** no JNI-port test. A backend/real-device integration test is
  still needed only if the redirect behind a banner's click URL is expected to invoke
  `/referral/check-by-click` and return to an SDK-owned offer surface.
- **Port required:** **No.**

### 9. Security-check JNI hardening

- **Status:** `NOT_APPLICABLE_TO_SWIFT`
- **Unity commit / file / symbol:** `9ecca65` —
  `Runtime/Core/SecurityCheck.cs`, `IsDeviceClean`, `IsRooted`, and new
  Android-only `CallStaticStringSafe` / `ClearPendingException`.
- **Actual Unity behaviour change:** Android security probes avoid reflective JNI;
  failure remains fail-open (`clean`/not-rooted). The Unity iOS native security calls
  are unchanged.
- **Swift equivalent:** `DeviceInfoProvider` performs iOS jailbreak-path/write and
  suspicious URL-scheme checks; `ZeyWinSDK.makeDeviceReport(...)` turns those values
  into `root_access` / `suspicious_apps`, and `SDKDeviceReportRequest` serializes the
  report.
- **Difference / risk:** platform-specific implementations intentionally differ.
  The Android fail-open policy has no JNI analogue in Swift. Risk is low for this
  commit; changes to Swift's jailbreak policy would need security-owner review.
- **Existing test coverage:** `testReportDevicePostsUnityCompatiblePayload` and
  `testDeviceReportEncodesCompletePayloadAndDecodesBlockedState` cover report
  encoding using fixture data; `SDKDeviceE2ETests` covers blocked-device outcomes.
  They do not perform live jailbreak/scheme detection.
- **Recommended test:** fixture-driven classification/encoding tests for jailbreak,
  suspicious-app, simulator, and clean cases; do not emulate a real jailbreak in CI.
- **Port required:** **No.**

### 10. Deferred Unity initialization

- **Status:** `NOT_APPLICABLE_TO_SWIFT`
- **Unity commit / file / symbol:** `9ecca65` — `Runtime/ZeyWinAds.cs`,
  `Initialize`, `InitializeAfterFirstSceneRoutine`, and `InitializeCore`.
- **Actual Unity behaviour change:** all Unity initialization is deferred until the
  first scene is loaded plus two frames, avoiding Android ART/Play Services/Firebase
  cold-start crashes. The commit explicitly documents a trade-off: the game can be
  visible before the loader/offer settles.
- **Swift equivalent:** `ZeyWinSDK.initialize(...)` only configures the SDK. Network,
  device collection, referral, loader presentation, and content resolution begin
  later in the explicit async `start(from:)` call on a UIKit view controller. There
  is no Unity scene lifecycle, Java reflection, ART, or Firebase JNI path.
- **Difference / risk:** copying a two-frame delay would add arbitrary latency to a
  native iOS API and could make loader timing worse. No shared behavioural contract
  requires it. Risk is low for parity and high for an automatic timing port.
- **Existing test coverage:** `SDKDeviceE2ETests` has an internal constructor seam
  for `APIClientProtocol`, `ContentPresenting`, and `PromotionURLStore`; its referral,
  blocked, invalid-URL, missing-creative, and network-failure tests exercise
  `initialize` → `start` outcomes deterministically. It correctly does not encode
  Unity's two-frame delay.
- **Recommended test:** add a real `ContentPresenter` loader-window lifecycle test
  only if more presentation coverage is required. Do not encode Unity frame timing.
- **Port required:** **No.**

## Real Swift parity gaps and priorities

1. **P1 — assert the real loader-window lifecycle.** The implementation already uses
   `SDKOverlayWindow`; E2E tests verify logical loading order. Add a simulator test
   that observes the actual window existence, level, and cleanup if this UI invariant
   must become a regression guarantee. This is coverage work, not a demonstrated port
   requirement.
2. **P2 — device capability boundary.** Complete request and blocked-state fixtures
   are tested. Live IDFV/SIM, jailbreak/suspicious-scheme detection, media playback,
   external-app opening, status-bar/safe-area, and accessibility focus remain
   simulator/real-device QA boundaries and must not be faked in unit tests.
3. **P3 — release policy decision.** Decide whether `SDKInitRequest.sdkVersion` is
   managed independently per SDK (the present implementation) or must be refreshed
   during every release. This is a release-process decision, not a source sync.

## What stage 6.3 can safely automate

- Fetch the fixed Unity range, regenerate the path-level report, and run this
  semantic-report template without modifying either SDK.
- Flag iOS changes that create/use a `UIWindow`, modify a request/response model, or
  alter referral/offer state as **review candidates** with mapped Swift paths.
- Run deterministic Swift unit/API/persistence/WebView/E2E tests after a
  human-approved Swift patch.
- Generate a proposed test matrix from concrete changed symbols.

## What must remain human-reviewed

- A host that owns an independent `UIWindow` or non-UIKit renderer surface; the
  resolved full-screen UIKit-modal case does not establish that separate scenario.
- Any camera, permission, motion, jailbreak/security, ATT, attribution, or
  deep-link capability change; these have platform/privacy implications.
- Backend version compatibility and the semantic meaning of version telemetry.
- Actual WebView rendering, video playback, external-app opening, safe area, and
  accessibility on physical devices.

## Conclusion

The analysed Unity changes are mostly Android cold-start/JNI hardening. On
`tests/ios-sdk-coverage`, the native iOS loader, referral/persistence flow, and
WebView/device E2E coverage are materially more complete than in the earlier
checkout. Stage 6.3 now has an app-hosted UIKit reproduction: the offer is visible
above an active full-screen host modal, closes cleanly, and leaves no SDK window.
The current minimal topmost-presenter behavior resolves this Unity parity item; do
not add a dedicated offer `UIWindow`.

No production source was edited during the host-test implementation. With this
verified current source state, there is no remaining 6.3 blocker to advancing
`.sync/unity-last-synced-commit` to `a7ade59`; it remains unchanged here because the
task explicitly forbids updating it without confirmation.
