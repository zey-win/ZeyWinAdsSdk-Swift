import UIKit

final class SDKPromoModalView: UIView {
    private let content: SDKBannerContent
    private let onClick: (URL) -> Void
    private let onClose: () -> Void

    private let containerView = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)

    init(content: SDKBannerContent, onClick: @escaping (URL) -> Void, onClose: @escaping () -> Void) {
        self.content = content
        self.onClick = onClick
        self.onClose = onClose
        super.init(frame: .zero)
        setupUI()
        bind()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor(red: 9 / 255, green: 20 / 255, blue: 36 / 255, alpha: 1)
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor(red: 32 / 255, green: 48 / 255, blue: 76 / 255, alpha: 1).cgColor
        containerView.clipsToBounds = true
        addSubview(containerView)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("x", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        containerView.addSubview(closeButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        containerView.addSubview(titleLabel)

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        bodyLabel.textColor = UIColor(white: 0.78, alpha: 1)
        bodyLabel.numberOfLines = 1
        containerView.addSubview(bodyLabel)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.backgroundColor = UIColor(red: 35 / 255, green: 55 / 255, blue: 80 / 255, alpha: 1)
        primaryButton.layer.cornerRadius = 4
        primaryButton.setTitleColor(.white, for: .normal)
        primaryButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        primaryButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        containerView.addSubview(primaryButton)

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.backgroundColor = UIColor(red: 38 / 255, green: 198 / 255, blue: 89 / 255, alpha: 1)
        secondaryButton.layer.cornerRadius = 4
        secondaryButton.setTitleColor(.white, for: .normal)
        secondaryButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        secondaryButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        containerView.addSubview(secondaryButton)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -6),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),

            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            primaryButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            primaryButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            primaryButton.heightAnchor.constraint(equalToConstant: 34),

            secondaryButton.leadingAnchor.constraint(equalTo: primaryButton.trailingAnchor, constant: 10),
            secondaryButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            secondaryButton.bottomAnchor.constraint(equalTo: primaryButton.bottomAnchor),
            secondaryButton.widthAnchor.constraint(equalTo: primaryButton.widthAnchor),
            secondaryButton.heightAnchor.constraint(equalTo: primaryButton.heightAnchor)
        ])
    }

    private func bind() {
        titleLabel.text = content.title.isEmpty ? "Try your luck!" : content.title
        bodyLabel.text = (content.body?.isEmpty == false ? content.body : "Play and win today")
        primaryButton.setTitle(content.ctaText.isEmpty ? "Play now" : content.ctaText, for: .normal)
        secondaryButton.setTitle(content.secondaryCTAText?.isEmpty == false ? content.secondaryCTAText : "Learn more", for: .normal)
    }

    @objc private func handleTap() {
        onClick(content.targetURL)
    }

    @objc private func handleClose() {
        removeFromSuperview()
        onClose()
    }
}
