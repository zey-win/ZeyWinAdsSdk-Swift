import UIKit

final class SDKBannerView: UIControl {
    private let content: SDKBannerContent
    private let onClick: (URL) -> Void

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let ctaContainerView = UIView()
    private let ctaLabel = UILabel()
    private let ctaButton = UIButton(type: .custom)

    init(content: SDKBannerContent, onClick: @escaping (URL) -> Void) {
        self.content = content
        self.onClick = onClick
        super.init(frame: .zero)
        setupUI()
        bind()
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        clipsToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 4
        iconView.backgroundColor = UIColor(red: 230 / 255, green: 238 / 255, blue: 245 / 255, alpha: 1)
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .black
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        addSubview(titleLabel)

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 10, weight: .regular)
        bodyLabel.textColor = .black
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 1
        bodyLabel.adjustsFontSizeToFitWidth = true
        bodyLabel.minimumScaleFactor = 0.65
        addSubview(bodyLabel)

        ctaContainerView.translatesAutoresizingMaskIntoConstraints = false
        ctaContainerView.backgroundColor = UIColor(red: 38 / 255, green: 198 / 255, blue: 89 / 255, alpha: 1)
        ctaContainerView.isUserInteractionEnabled = true
        addSubview(ctaContainerView)

        ctaLabel.translatesAutoresizingMaskIntoConstraints = false
        ctaLabel.font = .systemFont(ofSize: 8.5, weight: .bold)
        ctaLabel.textColor = .white
        ctaLabel.textAlignment = .center
        ctaLabel.backgroundColor = .clear
        ctaLabel.adjustsFontSizeToFitWidth = true
        ctaLabel.minimumScaleFactor = 0.42
        ctaContainerView.addSubview(ctaLabel)

        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        ctaButton.backgroundColor = .clear
        ctaButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        ctaContainerView.addSubview(ctaButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 54),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 105),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: bodyLabel.leadingAnchor, constant: -10),

            bodyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            bodyLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 50),
            bodyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
            bodyLabel.trailingAnchor.constraint(lessThanOrEqualTo: ctaContainerView.leadingAnchor, constant: -10),

            ctaContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ctaContainerView.topAnchor.constraint(equalTo: topAnchor),
            ctaContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ctaContainerView.widthAnchor.constraint(equalToConstant: 166),

            ctaLabel.leadingAnchor.constraint(equalTo: ctaContainerView.leadingAnchor, constant: 12),
            ctaLabel.trailingAnchor.constraint(equalTo: ctaContainerView.trailingAnchor, constant: -50),
            ctaLabel.centerYAnchor.constraint(equalTo: ctaContainerView.centerYAnchor),

            ctaButton.leadingAnchor.constraint(equalTo: ctaContainerView.leadingAnchor),
            ctaButton.trailingAnchor.constraint(equalTo: ctaContainerView.trailingAnchor),
            ctaButton.topAnchor.constraint(equalTo: ctaContainerView.topAnchor),
            ctaButton.bottomAnchor.constraint(equalTo: ctaContainerView.bottomAnchor)
        ])
    }

    private func bind() {
        titleLabel.text = content.title.isEmpty ? "Play now" : content.title
        bodyLabel.text = (content.body?.isEmpty == false ? content.body : "Play and win today")
        ctaLabel.text = (content.ctaText.isEmpty ? "Play now" : content.ctaText)

        if let imageURL = content.iconURL ?? content.mediaURL {
            loadImage(from: imageURL)
        }
    }

    @objc private func handleTap() {
        onClick(content.targetURL)
    }

    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.iconView.image = image
            }
        }.resume()
    }
}
