import UIKit

final class SDKLoadingViewController: UIViewController {
    private let progressTrackView = UIView()
    private let progressFillView = UIView()
    private let moneyView = SDKMoneyStackView()
    private let loadingLabel = UILabel()

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var progressFillWidthConstraint: NSLayoutConstraint?
    private var moneyCenterXConstraint: NSLayoutConstraint?

    private let progressTimes: [CGFloat] = [0, 0.08, 0.14, 0.27, 0.34, 0.48, 0.58, 0.71, 0.83, 0.93, 1]
    private let progressValues: [CGFloat] = [0, 0.03, 0.12, 0.18, 0.36, 0.45, 0.62, 0.70, 0.86, 0.92, 0.98]
    private let cycleDuration: CFTimeInterval = 8

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startAnimation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAnimation()
    }

    deinit {
        displayLink?.invalidate()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(red: 22 / 255, green: 34 / 255, blue: 171 / 255, alpha: 1)

        progressTrackView.translatesAutoresizingMaskIntoConstraints = false
        progressTrackView.backgroundColor = UIColor(red: 38 / 255, green: 70 / 255, blue: 165 / 255, alpha: 1)
        progressTrackView.layer.cornerRadius = 8
        progressTrackView.layer.borderWidth = 2
        progressTrackView.layer.borderColor = UIColor.white.cgColor
        progressTrackView.clipsToBounds = true
        view.addSubview(progressTrackView)

        progressFillView.translatesAutoresizingMaskIntoConstraints = false
        progressFillView.backgroundColor = UIColor(red: 255 / 255, green: 196 / 255, blue: 39 / 255, alpha: 1)
        progressFillView.layer.cornerRadius = 6
        progressFillView.clipsToBounds = true
        progressTrackView.addSubview(progressFillView)

        moneyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(moneyView)

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.font = .systemFont(ofSize: 18, weight: .bold)
        loadingLabel.textColor = .white
        loadingLabel.textAlignment = .center
        loadingLabel.text = "Loading 0%"
        view.addSubview(loadingLabel)

        progressFillWidthConstraint = progressFillView.widthAnchor.constraint(equalToConstant: 2)
        moneyCenterXConstraint = moneyView.centerXAnchor.constraint(equalTo: progressTrackView.leadingAnchor, constant: 8)

        NSLayoutConstraint.activate([
            progressTrackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressTrackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 155),
            progressTrackView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.52),
            progressTrackView.heightAnchor.constraint(equalToConstant: 16),

            progressFillView.leadingAnchor.constraint(equalTo: progressTrackView.leadingAnchor, constant: 3),
            progressFillView.centerYAnchor.constraint(equalTo: progressTrackView.centerYAnchor),
            progressFillView.heightAnchor.constraint(equalToConstant: 10),
            progressFillWidthConstraint!,

            moneyView.centerYAnchor.constraint(equalTo: progressTrackView.centerYAnchor, constant: -2),
            moneyView.widthAnchor.constraint(equalToConstant: 34),
            moneyView.heightAnchor.constraint(equalToConstant: 44),
            moneyCenterXConstraint!,

            loadingLabel.topAnchor.constraint(equalTo: progressTrackView.bottomAnchor, constant: 18),
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
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

    private func updateAnimation() {
        let elapsed = CACurrentMediaTime() - startTime
        let normalized = CGFloat(min(max(elapsed / cycleDuration, 0), 1))
        let progress = steppedProgress(at: normalized)
        let pulse = 0.985 + sin(elapsed * 4.2) * 0.015
        let displayProgress = min(0.99, progress * CGFloat(pulse))

        let trackWidth = max(progressTrackView.bounds.width, 1)
        progressFillWidthConstraint?.constant = max(2, (trackWidth - 6) * displayProgress)
        moneyCenterXConstraint?.constant = 8 + max(0, trackWidth - 16) * displayProgress

        let angle = sin(elapsed * 5.5) * 0.17
        let bounce = sin(elapsed * 8.0) * 2.5
        moneyView.transform = CGAffineTransform(translationX: 0, y: bounce).rotated(by: angle)
        loadingLabel.text = "Loading \(Int(displayProgress * 100))%"
    }

    private func steppedProgress(at time: CGFloat) -> CGFloat {
        guard let firstTime = progressTimes.first,
              let firstValue = progressValues.first,
              time > firstTime else { return progressValues.first ?? 0 }

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

private final class SDKMoneyStackView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setAllowsAntialiasing(true)

        let billColors = [
            UIColor(red: 41 / 255, green: 206 / 255, blue: 63 / 255, alpha: 1),
            UIColor(red: 91 / 255, green: 237 / 255, blue: 68 / 255, alpha: 1),
            UIColor(red: 23 / 255, green: 176 / 255, blue: 58 / 255, alpha: 1)
        ]

        let offsets: [CGFloat] = [10, 4, 0]
        for (index, offset) in offsets.enumerated() {
            let bill = CGRect(x: 6 + offset * 0.18, y: offset, width: rect.width - 10, height: rect.height - 14)
            let path = UIBezierPath(roundedRect: bill, cornerRadius: 4)
            billColors[index].setFill()
            path.fill()
            UIColor(red: 9 / 255, green: 103 / 255, blue: 36 / 255, alpha: 1).setStroke()
            path.lineWidth = 1.2
            path.stroke()

            let band = CGRect(x: bill.midX - 4, y: bill.minY + 2, width: 8, height: bill.height - 4)
            UIColor(red: 255 / 255, green: 202 / 255, blue: 45 / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: band, cornerRadius: 2).fill()
        }
    }
}
