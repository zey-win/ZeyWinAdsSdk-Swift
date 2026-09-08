import UIKit

final class SDKLoadingViewController: UIViewController {

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }

    override var shouldAutorotate: Bool {
        true
    }
    private static let moneyImageBase64 = """
    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
    Bc1bkxgTs5gPAAAAAElFTkSuQmCC
    """
    private static let moneyImage: UIImage? = {
        guard let data = Data(
            base64Encoded: moneyImageBase64,
            options: .ignoreUnknownCharacters
        ) else {
            return nil
        }
        return UIImage(data: data)
    }()
    private let progressTrackView = UIView()
    private let progressFillView = UIView()
    private let moneyView = UIImageView(image: SDKLoadingViewController.moneyImage)
    private let loadingLabel = UILabel()

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var currentProgress: CGFloat = 0
    private var isFinishing = false
    private var finishStartTime: CFTimeInterval?
    private var finishStartProgress: CGFloat = 0
    private var finishDuration: CFTimeInterval = 0
    private var finishCompletion: (() -> Void)?

    private let progressTimes: [CGFloat] = [0, 0.08, 0.14, 0.27, 0.34, 0.48, 0.58, 0.71, 0.83, 0.93, 1]
    private let progressValues: [CGFloat] = [0, 0.03, 0.12, 0.18, 0.36, 0.45, 0.62, 0.70, 0.86, 0.92, 1]
    private let cycleDuration: CFTimeInterval = 8

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startAnimation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutProgressViews()
    }

    deinit {
        displayLink?.invalidate()
    }

    private func setupUI() {
        view.isOpaque = true
        view.alpha = 1
        view.backgroundColor = UIColor(red: 15 / 255, green: 33 / 255, blue: 158 / 255, alpha: 1)

        progressTrackView.backgroundColor = UIColor(red: 28 / 255, green: 42 / 255, blue: 105 / 255, alpha: 1)
        progressTrackView.layer.borderWidth = 3
        progressTrackView.layer.borderColor = UIColor(red: 238 / 255, green: 247 / 255, blue: 255 / 255, alpha: 1).cgColor
        progressTrackView.clipsToBounds = true
        view.addSubview(progressTrackView)

        progressFillView.backgroundColor = UIColor(red: 255 / 255, green: 188 / 255, blue: 41 / 255, alpha: 1)
        progressFillView.clipsToBounds = true
        progressTrackView.addSubview(progressFillView)

        moneyView.backgroundColor = .clear
        moneyView.contentMode = .scaleAspectFit
        moneyView.clipsToBounds = false
        moneyView.layer.zPosition = 2
        view.addSubview(moneyView)

        loadingLabel.font = .systemFont(ofSize: 22, weight: .bold)
        loadingLabel.textColor = .white
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 1
        loadingLabel.text = "Loading 0%"
        view.addSubview(loadingLabel)
    }

    private func startAnimation() {
        startTime = CACurrentMediaTime()
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        updateAnimation()
    }

    func completeAndDismiss(completion: @escaping () -> Void) {
        guard !isFinishing else { return }

        isFinishing = true
        finishStartTime = CACurrentMediaTime()
        finishStartProgress = currentProgress
        finishDuration = max(1.5, (1 - currentProgress) * cycleDuration)
        finishCompletion = completion
    }

    private func updateAnimation() {
        let now = CACurrentMediaTime()

        if isFinishing {
            guard let finishStartTime, let finishCompletion else { return }

            let elapsed = now - finishStartTime
            let normalized = CGFloat(min(max(elapsed / finishDuration, 0), 1))
            let eased = normalized * normalized * (3 - 2 * normalized)
            applyProgress(finishStartProgress + (1 - finishStartProgress) * eased)

            if normalized >= 1 {
                displayLink?.invalidate()
                displayLink = nil
                self.finishCompletion = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    finishCompletion()
                }
            }
            return
        }

        let elapsed = now - startTime
        let normalized = CGFloat(min(max(elapsed / cycleDuration, 0), 1))
        applyProgress(steppedProgress(at: normalized))
    }

    private func applyProgress(_ progress: CGFloat) {
        currentProgress = min(max(progress, currentProgress), 1)
        loadingLabel.text = "Loading \(Int((currentProgress * 100).rounded()))%"
        layoutProgressViews()
    }

    private func layoutProgressViews() {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }

        let landscape = view.bounds.width > view.bounds.height
        let maxBarWidth = max(96, view.bounds.width - 32)
        let requestedBarWidth = view.bounds.width * (landscape ? 0.50 : 0.70)
        let barWidth = min(max(96, requestedBarWidth), maxBarWidth)
        let barLeft = max(16, (view.bounds.width - barWidth) * 0.5)
        let barRight = min(view.bounds.width - 16, barLeft + barWidth)
        let barHeight: CGFloat = 30
        let labelGap: CGFloat = landscape ? 20 : 30
        let labelHeight: CGFloat = landscape ? 30 : 34
        let contentHeight = barHeight + labelGap + labelHeight
        let barTop: CGFloat
        if landscape {
            barTop = max(0, (view.bounds.height - contentHeight) * 0.5)
        } else {
            let bottomPadding = max(32, view.safeAreaInsets.bottom + 24)
            let lowerPosition = view.bounds.height * 0.68
            let latestPosition = view.bounds.height - bottomPadding - contentHeight
            barTop = max(0, min(lowerPosition, latestPosition))
        }
        let barBottom = barTop + barHeight
        let radius = barHeight * 0.5
        let moneyX = barLeft + radius + (barRight - barLeft - radius * 2) * currentProgress

        progressTrackView.frame = CGRect(
            x: barLeft,
            y: barTop,
            width: barRight - barLeft,
            height: barHeight
        )
        progressTrackView.layer.cornerRadius = radius

        let fillWidth = max(0, max(barLeft + 28, moneyX) - barLeft - 4)
        progressFillView.frame = CGRect(
            x: 4,
            y: 4,
            width: fillWidth,
            height: max(1, barHeight - 8)
        )
        progressFillView.layer.cornerRadius = max(1, radius - 4)

        let targetHeight: CGFloat = 72
        let targetWidth: CGFloat
        if let image = moneyView.image, image.size.height > 0 {
            targetWidth = targetHeight * image.size.width / image.size.height
        } else {
            targetWidth = 64
        }
        let minX = targetWidth * 0.5 + 22
        let maxX = max(minX, view.bounds.width - targetWidth * 0.5 - 22)
        let clampedMoneyX = min(max(moneyX, minX), maxX)
        moneyView.frame = CGRect(
            x: clampedMoneyX - targetWidth * 0.5,
            y: barTop + 16 - targetHeight * 0.5,
            width: targetWidth,
            height: targetHeight
        )

        loadingLabel.font = .systemFont(ofSize: landscape ? 22 : 25, weight: .bold)
        loadingLabel.frame = CGRect(
            x: 16,
            y: barBottom + labelGap,
            width: view.bounds.width - 32,
            height: labelHeight
        )
    }

    private func steppedProgress(at time: CGFloat) -> CGFloat {
        guard let firstTime = progressTimes.first,
              let firstValue = progressValues.first else { return 0 }
        guard time > firstTime else { return firstValue }

        for index in 1..<progressTimes.count {
            let nextTime = progressTimes[index]
            if time <= nextTime {
                let previousTime = progressTimes[index - 1]
                let previousValue = progressValues[index - 1]
                let nextValue = progressValues[index]
                let segment = max(nextTime - previousTime, 0.0001)
                let local = (time - previousTime) / segment
                let eased = local * local * (3 - 2 * local)
                return previousValue + (nextValue - previousValue) * eased
            }
        }

        return progressValues.last ?? firstValue
    }
}
