import AVFoundation
import UIKit
import WebKit

@MainActor
final class SDKWebViewController: UIViewController {

    private let url: URL
    private let clickThroughURL: URL?
    private let tracking: SDKAdTracking?
    private let durationSec: Int?
    private let skipAfterSec: Int?
    private let onClose: (() -> Void)?
    private var didNotifyClose = false
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

    private let playerView = SDKVideoPlayerView()
    private let progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.22)
        progressView.progressTintColor = .white
        progressView.progress = 0
        return progressView
    }()
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.text = "0:00"
        return label
    }()

    private let webView = WKWebView(
        frame: .zero,
        configuration: SDKWebViewController.makeWebViewConfiguration()
    )
    private let clickOverlay = UIControl()
    private let closeButton = UIButton(type: .system)

    init(
        url: URL,
        clickThroughURL: URL? = nil,
        tracking: SDKAdTracking?,
        durationSec: Int? = nil,
        skipAfterSec: Int? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.url = url
        self.clickThroughURL = clickThroughURL
        self.tracking = tracking
        self.durationSec = durationSec
        self.skipAfterSec = skipAfterSec
        self.onClose = onClose
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
            setupNativeVideoPlayer()
            setupClickOverlayIfNeeded()
            setupVideoProgress()
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


    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        player?.pause()
        closeTimer?.invalidate()
        removePlaybackObservers()
        notifyCloseIfNeeded()
    }

    deinit {
        closeTimer?.invalidate()
    }

    private func setupNativeVideoPlayer() {
        playerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        self.player = player
        playerView.player = player

        playerStatusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.trackWebViewShownIfNeeded()
                    self?.player?.play()

                case .failed:
                    SDKLogger.log("Video playback failed: \(item.error?.localizedDescription ?? "unknown")")
                    self?.trackWebViewFailure(reason: "video_error")

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

        view.addSubview(webView)

        NSLayoutConstraint.activate(
            [
                webView.topAnchor.constraint(
                    equalTo: view.topAnchor
                ),
                webView.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor
                ),
                webView.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor
                ),
                webView.bottomAnchor.constraint(
                    equalTo: view.bottomAnchor
                )
            ]
        )

        webView.load(
            URLRequest(url: url)
        )
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
    }


    private func setupVideoProgress() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(progressView)
        view.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            progressView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            progressView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),

            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: progressView.topAnchor, constant: -8)
        ])
    }

    private func updateVideoProgress(currentTime: CMTime) {
        guard let item = player?.currentItem else {
            return
        }

        let current = CMTimeGetSeconds(currentTime)
        let duration = resolvedVideoDuration(for: item)

        guard duration > 0, current.isFinite else {
            progressView.progress = 0
            timeLabel.text = formatTime(current)
            return
        }

        progressView.progress = Float(min(max(current / duration, 0), 1))
        timeLabel.text = "\(formatTime(current)) / \(formatTime(duration))"
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

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else {
            return "0:00"
        }

        let totalSeconds = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func completeVideoAndUnlockClose() {
        trackCompleteIfNeeded()
        canClose = true
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
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        closeButton.tintColor = .white
        closeButton.layer.cornerRadius = 22
        closeButton.clipsToBounds = true
        closeButton.setTitle("x", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .regular)
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
                self?.showCloseButton()
            }
        }
    }

    private func showCloseButton() {
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

    private func isDirectVideoURL(
        _ url: URL
    ) -> Bool {
        let path = url.path.lowercased()

        return path.hasSuffix(".mp4")
            || path.hasSuffix(".mov")
            || path.hasSuffix(".m4v")
            || path.hasSuffix(".webm")
    }

    private static func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        return configuration
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
            trackWebViewShownIfNeeded()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
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
            trackWebViewShownIfNeeded()

        case "webview-failed":
            trackWebViewFailure(
                reason: "video_error"
            )

        default:
            break
        }

        return true
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        if isPluginHandledLoadError(error) {
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
