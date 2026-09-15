import AVFoundation
import UIKit
import WebKit

@MainActor
final class SDKWebViewController: UIViewController {

    private static let externallyHandledSchemes: Set<String> = [
        "tg",
        "telegram",
        "whatsapp",
        "viber",
        "intent",
        "market"
    ]

    private let orientationMask: UIInterfaceOrientationMask

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientationMask
    }

    override var shouldAutorotate: Bool {
        true
    }

    private let url: URL
    private let clickThroughURL: URL?
    private let mediaType: String?
    private let tracking: SDKAdTracking?
    private let durationSec: Int?
    private let skipAfterSec: Int?
    private let onClose: (() -> Void)?
    private let onReady: (() -> Void)?
    private let externalURLHandler: @MainActor (URL) -> Void
    private var didNotifyClose = false
    private var didNotifyReady = false
    private var didSendClickTracking = false
    private var didSendShownTracking = false
    private var didSendFailedTracking = false
    private var didSendCompleteTracking = false
    private var canClose = false
    private var closeTimer: Timer?
    private var player: AVPlayer?
    private var playbackObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var playerStatusObservation: NSKeyValueObservation?
    private var videoProgressTimer: Timer?
    private var videoStartTime: CFTimeInterval = 0
    private var didActivateVideoAudioSession = false
    private var nativeVideoFallbackTimer: Timer?
    private var isUsingNativeVideoPlayer = false
    private var didLoadInlineVideoHTML = false
    private var isUsingInlineVideoWebView = false

    private let playerView = SDKVideoPlayerView()
    private let countdownLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 30, weight: .regular)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        label.layer.cornerRadius = 0
        label.clipsToBounds = true
        label.isHidden = false
        return label
    }()

    let webView = WKWebView(
        frame: .zero,
        configuration: SDKWebViewController.makeWebViewConfiguration()
    )
    private let clickOverlay = UIControl()
    private let closeButton = UIButton(type: .system)

    init(
        url: URL,
        clickThroughURL: URL? = nil,
        mediaType: String? = nil,
        tracking: SDKAdTracking?,
        durationSec: Int? = nil,
        skipAfterSec: Int? = nil,
        orientationMask: UIInterfaceOrientationMask = .landscape,
        onClose: (() -> Void)? = nil,
        onReady: (() -> Void)? = nil,
        externalURLHandler: @escaping @MainActor (URL) -> Void = SDKWebViewController.openExternally
    ) {
        self.url = url
        self.clickThroughURL = clickThroughURL
        self.mediaType = mediaType
        self.tracking = tracking
        self.durationSec = durationSec
        self.skipAfterSec = skipAfterSec
        self.orientationMask = orientationMask
        self.onClose = onClose
        self.onReady = onReady
        self.externalURLHandler = externalURLHandler
        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        if isDirectVideoURL(url) {
            if supportsNativeVideoPlayback(url) {
                setupNativeVideoPlayer()
            } else {
                activateVideoAudioSession()
                setupInlineVideoWebView()
            }
            setupClickOverlayIfNeeded()
            setupVideoCountdown()
            startVideoProgressTimer()
            setupCloseButtonIfNeeded()
        } else {
            setupWebView()
            setupClickOverlayIfNeeded()
            setupCloseButtonIfNeeded()
        }

        SDKTrackingClient.shared.fire(
            tracking,
            event: "impression"
        )
    }


    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layoutIfNeeded()
        playerView.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerView.playerLayer.frame = playerView.bounds
        loadInlineVideoHTMLIfNeeded()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.view.layoutIfNeeded()
            self.playerView.playerLayer.frame = self.playerView.bounds
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        notifyCloseIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player?.pause()
        nativeVideoFallbackTimer?.invalidate()
        nativeVideoFallbackTimer = nil
        deactivateVideoAudioSession()
        closeTimer?.invalidate()
        videoProgressTimer?.invalidate()
        removePlaybackObservers()
        notifyCloseIfNeeded()
    }

    deinit {
        nativeVideoFallbackTimer?.invalidate()
        closeTimer?.invalidate()
        videoProgressTimer?.invalidate()
    }

    private func activateVideoAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try audioSession.setActive(true)
            didActivateVideoAudioSession = true
        } catch {
            SDKLogger.log("Video audio session failed: \(error.localizedDescription)")
        }
    }

    private func deactivateVideoAudioSession() {
        guard didActivateVideoAudioSession else {
            return
        }

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        didActivateVideoAudioSession = false
    }

    private func setupInlineVideoWebView() {
        isUsingInlineVideoWebView = true
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.contentOffset = .zero

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // HTML is intentionally NOT loaded here. On a real device this view
        // controller is created while the interface is still rotating into
        // its final landscape size, so webView.bounds at this point can be
        // a stale/intermediate frame. WebKit lays out the document against
        // whatever size it sees at load time and does not always re-flow it
        // once the real frame lands, which is what produced the visible gap
        // on the right/bottom. Loading is deferred to
        // loadInlineVideoHTMLIfNeeded(), called from viewDidLayoutSubviews(),
        // once webView has a real, non-zero bounds.
    }

    private func loadInlineVideoHTMLIfNeeded() {
        guard
            isUsingInlineVideoWebView,
            !didLoadInlineVideoHTML,
            webView.superview != nil,
            webView.bounds.width > 0,
            webView.bounds.height > 0
        else {
            return
        }

        didLoadInlineVideoHTML = true
        webView.loadHTMLString(
            makeInlineVideoHTML(for: url),
            baseURL: url.deletingLastPathComponent()
        )

        // Native playback can fall back to this WebView after the click layer
        // has already been installed. Keep the video controls above the new view.
        bringVideoControlsToFront()
    }

    private func bringVideoControlsToFront() {
        if clickOverlay.superview != nil {
            view.bringSubviewToFront(clickOverlay)
        }

        if countdownLabel.superview != nil {
            view.bringSubviewToFront(countdownLabel)
        }

        if closeButton.superview != nil {
            view.bringSubviewToFront(closeButton)
        }
    }

    private func makeInlineVideoHTML(for videoURL: URL) -> String {
        let source = videoURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
          <style>
            html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
            body { position: fixed; inset: 0; }
            video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: center center; background: #000; pointer-events: none; }
            * { -webkit-user-select: none; -webkit-touch-callout: none; user-select: none; }
          </style>
        </head>
        <body>
          <video id="adVideo" autoplay playsinline webkit-playsinline preload="auto" disablepictureinpicture controlslist="nodownload nofullscreen noremoteplayback">
            <source src="\(source)">
          </video>
          <script>
            const video = document.getElementById('adVideo');
            let shown = false;
            function notify(name) { window.location.href = 'zeywin-sdk://' + name; }
            function markShown() { if (!shown) { shown = true; notify('webview-shown'); } }
            video.controls = false;
            video.muted = false;
            video.volume = 1;
            video.disablePictureInPicture = true;
            video.addEventListener('playing', markShown);
            video.addEventListener('canplay', function() { video.play().then(markShown).catch(function() {}); });
            video.addEventListener('ended', function() { notify('webview-complete'); });
            video.addEventListener('error', function() { notify('webview-failed'); });
            document.addEventListener('visibilitychange', function() { if (!document.hidden) { video.play().catch(function() {}); } });
            setTimeout(function retryPlay() {
              if (video.paused && !video.ended) { video.play().catch(function() {}); setTimeout(retryPlay, 700); }
            }, 250);
          </script>
        </body>
        </html>
        """
    }

    private func setupNativeVideoPlayer() {
        isUsingNativeVideoPlayer = true
        playerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        activateVideoAudioSession()
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = false
        player.volume = 1
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = true
        self.player = player
        playerView.player = player
        nativeVideoFallbackTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isUsingNativeVideoPlayer else { return }
                guard let player = self.player else {
                    self.fallbackToWebViewVideo()
                    return
                }

                let status = player.currentItem?.status
                let currentTime = player.currentTime().seconds
                let hasStarted = currentTime.isFinite && currentTime > 0.1
                guard status == .readyToPlay, (player.timeControlStatus == .playing || hasStarted) else {
                    SDKLogger.log("Native video did not start in time")
                    self.fallbackToWebViewVideo()
                    return
                }
            }
        }

        playerStatusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.nativeVideoFallbackTimer?.invalidate()
                    self?.nativeVideoFallbackTimer = nil
                    self?.trackWebViewShownIfNeeded()
                    self?.player?.play()

                case .failed:
                    SDKLogger.log("Video playback failed: \(item.error?.localizedDescription ?? "unknown")")
                    self?.fallbackToWebViewVideo()

                default:
                    break
                }
            }
        }

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.completeVideoAndUnlockClose()
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        playbackObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.updateVideoProgress(currentTime: time)
            }
        }
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero

        view.addSubview(webView)

        NSLayoutConstraint.activate(
            [
                webView.topAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.topAnchor
                ),
                webView.leadingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.leadingAnchor
                ),
                webView.trailingAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.trailingAnchor
                ),
                webView.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor
                )
            ]
        )

        webView.load(
            URLRequest(url: url)
        )
    }

    private func fallbackToWebViewVideo() {
        guard isUsingNativeVideoPlayer else {
            handleNativeVideoFailure()
            return
        }

        isUsingNativeVideoPlayer = false
        nativeVideoFallbackTimer?.invalidate()
        nativeVideoFallbackTimer = nil
        player?.pause()
        removePlaybackObservers()
        player = nil
        playerView.removeFromSuperview()
        setupInlineVideoWebView()
        SDKLogger.log("Falling back to WebView video player")
    }

    private func handleNativeVideoFailure() {
        removePlaybackObservers()
        player?.pause()
        player = nil
        closeTimer?.invalidate()
        closeTimer = nil
        videoProgressTimer?.invalidate()
        videoProgressTimer = nil
        countdownLabel.isHidden = true
        trackWebViewFailure(reason: "video_playback_error")
        canClose = true
        showCloseButton()
    }

    private func setupClickOverlayIfNeeded() {
        guard clickThroughURL != nil else {
            return
        }

        clickOverlay.backgroundColor = .clear
        clickOverlay.translatesAutoresizingMaskIntoConstraints = false
        clickOverlay.addTarget(
            self,
            action: #selector(openClickThrough),
            for: .touchUpInside
        )
        view.addSubview(
            clickOverlay
        )

        NSLayoutConstraint.activate(
            [
                clickOverlay.topAnchor.constraint(
                    equalTo: view.topAnchor
                ),
                clickOverlay.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor
                ),
                clickOverlay.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor
                ),
                clickOverlay.bottomAnchor.constraint(
                    equalTo: view.bottomAnchor
                )
            ]
        )

        bringVideoControlsToFront()
    }


    private func setupVideoCountdown() {
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        countdownLabel.text = "\(resolvedAdDuration())"

        view.addSubview(countdownLabel)

        NSLayoutConstraint.activate([
            countdownLabel.widthAnchor.constraint(equalToConstant: 58),
            countdownLabel.heightAnchor.constraint(equalToConstant: 58),
            countdownLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            countdownLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])
    }

    private func startVideoProgressTimer() {
        videoProgressTimer?.invalidate()
        videoStartTime = CACurrentMediaTime()

        videoProgressTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateSyntheticVideoProgress()
            }
        }
    }

    private func updateSyntheticVideoProgress() {
        let duration = Double(resolvedAdDuration())
        guard duration > 0 else {
            return
        }

        let elapsed = max(0, CACurrentMediaTime() - videoStartTime)
        updateCloseCountdown(currentTime: elapsed)

        if elapsed >= duration {
            videoProgressTimer?.invalidate()
            videoProgressTimer = nil
            completeVideoAndUnlockClose()
        }
    }

    private func updateVideoProgress(currentTime: CMTime) {
        guard let item = player?.currentItem else {
            return
        }

        let current = CMTimeGetSeconds(currentTime)
        let duration = resolvedVideoDuration(for: item)

        guard duration > 0, current.isFinite else {
            updateCloseCountdown(currentTime: current)
            return
        }

        updateCloseCountdown(currentTime: current)
    }

    private func resolvedVideoDuration(for item: AVPlayerItem) -> Double {
        let itemDuration = CMTimeGetSeconds(item.duration)
        if itemDuration.isFinite, itemDuration > 0 {
            return itemDuration
        }

        if let durationSec, durationSec > 0 {
            return Double(durationSec)
        }

        return 0
    }

    private func updateCloseCountdown(currentTime: Double) {
        guard !canClose else {
            countdownLabel.isHidden = true
            return
        }

        let remaining = Double(resolvedAdDuration()) - currentTime
        countdownLabel.text = "\(max(0, Int(ceil(remaining))))"
        countdownLabel.isHidden = false
        view.bringSubviewToFront(countdownLabel)
    }

    private func resolvedAdDuration() -> Int {
        if let skipAfterSec, skipAfterSec > 0 {
            return skipAfterSec
        }

        if let durationSec, durationSec > 0 {
            return durationSec
        }

        return 30
    }

    private func completeVideoAndUnlockClose() {
        videoProgressTimer?.invalidate()
        videoProgressTimer = nil
        trackCompleteIfNeeded()
        canClose = true
        countdownLabel.isHidden = true
        showCloseButton()
    }

    private func removePlaybackObservers() {
        if let playbackObserver {
            player?.removeTimeObserver(playbackObserver)
            self.playbackObserver = nil
        }

        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }

        playerStatusObservation = nil
    }

    private func setupCloseButtonIfNeeded() {
        guard clickThroughURL != nil else {
            return
        }

        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.backgroundColor = .clear
        closeButton.tintColor = .white
        closeButton.layer.cornerRadius = 0
        closeButton.clipsToBounds = true
        let closeImageConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        closeButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: closeImageConfiguration),
            for: .normal
        )
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )

        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        ])
        view.bringSubviewToFront(closeButton)

        guard let skipAfterSec, skipAfterSec > 0 else {
            closeButton.isHidden = true
            return
        }

        let delay = TimeInterval(skipAfterSec)
        closeTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.canClose = true
                self?.countdownLabel.isHidden = true
                self?.showCloseButton()
            }
        }
    }

    private func showCloseButton() {
        countdownLabel.isHidden = true
        closeButton.isHidden = false
        view.bringSubviewToFront(closeButton)
    }

    @objc
    private func closeTapped() {
        guard canClose else {
            return
        }

        dismiss(animated: true)
    }

    private func supportsNativeVideoPlayback(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".mp4") || path.hasSuffix(".mov") || path.hasSuffix(".m4v")
    }

    private func isDirectVideoURL(
        _ url: URL
    ) -> Bool {
        let path = url.path.lowercased()
        let declaredType = mediaType?.lowercased() ?? ""

        return declaredType.contains("video")
            || path.hasSuffix(".mp4")
            || path.hasSuffix(".mov")
            || path.hasSuffix(".m4v")
            || path.hasSuffix(".webm")
    }

    static func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        return configuration
    }

    private static func openExternally(
        _ url: URL
    ) {
        UIApplication.shared.open(url)
    }

    @objc
    private func openClickThrough() {
        guard let clickThroughURL else {
            return
        }

        trackClickIfNeeded()

        if isDirectVideoURL(url) {
            UIApplication.shared.open(clickThroughURL)
            return
        }

        clickOverlay.removeFromSuperview()
        webView.load(
            URLRequest(url: clickThroughURL)
        )
    }
}

private final class SDKVideoPlayerView: UIView {

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get {
            playerLayer.player
        }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .black
        }
    }
}

extension SDKWebViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation?
    ) {
        if !isDirectVideoURL(url) {
            notifyReadyIfNeeded()
            trackWebViewShownIfNeeded()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if handleExternalNavigation(
            navigationAction.request.url
        ) {
            decisionHandler(.cancel)
            return
        }

        if handleSDKNavigation(
            navigationAction.request.url
        ) {
            decisionHandler(.cancel)
            return
        }

        if
            navigationAction.navigationType == .linkActivated,
            let clickThroughURL
        {
            trackClickIfNeeded()

            webView.load(
                URLRequest(url: clickThroughURL)
            )

            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    private func handleSDKNavigation(
        _ url: URL?
    ) -> Bool {
        guard url?.scheme == "zeywin-sdk" else {
            return false
        }

        switch url?.host {
        case "webview-shown":
            notifyReadyIfNeeded()
            trackWebViewShownIfNeeded()

        case "webview-failed":
            trackWebViewFailure(
                reason: "video_error"
            )
            canClose = true
            showCloseButton()

        case "webview-complete":
            completeVideoAndUnlockClose()

        default:
            break
        }

        return true
    }

    private func handleExternalNavigation(
        _ url: URL?
    ) -> Bool {
        guard let url, Self.externallyHandledSchemes.contains(url.scheme?.lowercased() ?? "") else {
            return false
        }

        externalURLHandler(url)
        return true
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        if isPluginHandledLoadError(error) {
            notifyReadyIfNeeded()
            trackWebViewShownIfNeeded()
            return
        }

        SDKLogger.log(
            "WebView navigation error: \(error.localizedDescription)"
        )

        trackWebViewFailure(
            reason: "html_load_error"
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        if isPluginHandledLoadError(error) {
            notifyReadyIfNeeded()
            trackWebViewShownIfNeeded()
            return
        }

        SDKLogger.log(
            "WebView provisional navigation error: \(error.localizedDescription)"
        )

        trackWebViewFailure(
            reason: "html_load_error"
        )
    }

    private func trackWebViewFailure(
        reason: String
    ) {
        guard
            !didSendShownTracking,
            !didSendFailedTracking
        else {
            return
        }

        notifyReadyIfNeeded()
        didSendFailedTracking = true
        SDKTrackingClient.shared.trackWebView(
            tracking,
            status: "failed",
            failReason: reason
        )
    }

    private func trackWebViewShownIfNeeded() {
        guard !didSendShownTracking else {
            return
        }

        didSendShownTracking = true
        SDKTrackingClient.shared.trackWebView(
            tracking,
            status: "shown"
        )
    }

    private func isPluginHandledLoadError(
        _ error: Error
    ) -> Bool {
        let nsError = error as NSError

        return nsError.domain == "WebKitErrorDomain"
            && nsError.code == 204
    }

    private func notifyReadyIfNeeded() {
        guard !didNotifyReady else {
            return
        }

        didNotifyReady = true
        onReady?()
    }

    private func notifyCloseIfNeeded() {
        guard !didNotifyClose else {
            return
        }

        didNotifyClose = true
        onClose?()
    }


    private func trackCompleteIfNeeded() {
        guard !didSendCompleteTracking else {
            return
        }

        didSendCompleteTracking = true
        SDKTrackingClient.shared.fire(
            tracking,
            event: "complete"
        )
    }

    private func trackClickIfNeeded() {
        guard !didSendClickTracking else {
            return
        }

        didSendClickTracking = true
        SDKTrackingClient.shared.fire(
            tracking,
            event: "click"
        )
    }
}
