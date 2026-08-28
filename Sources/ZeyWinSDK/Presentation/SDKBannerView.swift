import UIKit

final class SDKBannerView: UIControl {
    private let content: SDKBannerContent
    private let onClick: (URL) -> Void

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let ctaLabel = UILabel()

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
        iconView.layer.cornerRadius = 5
        iconView.backgroundColor = UIColor(red: 230 / 255, green: 238 / 255, blue: 245 / 255, alpha: 1)
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .black
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        addSubview(titleLabel)

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 13, weight: .regular)
        bodyLabel.textColor = .black
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 1
        bodyLabel.adjustsFontSizeToFitWidth = true
        bodyLabel.minimumScaleFactor = 0.65
        addSubview(bodyLabel)

        ctaLabel.translatesAutoresizingMaskIntoConstraints = false
        ctaLabel.font = .systemFont(ofSize: 11, weight: .bold)
        ctaLabel.textColor = .white
        ctaLabel.textAlignment = .center
        ctaLabel.backgroundColor = UIColor(red: 38 / 255, green: 198 / 255, blue: 89 / 255, alpha: 1)
        ctaLabel.adjustsFontSizeToFitWidth = true
        ctaLabel.minimumScaleFactor = 0.6
        addSubview(ctaLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 47),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: bodyLabel.leadingAnchor, constant: -12),

            bodyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            bodyLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 58),
            bodyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            bodyLabel.trailingAnchor.constraint(lessThanOrEqualTo: ctaLabel.leadingAnchor, constant: -12),

            ctaLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            ctaLabel.topAnchor.constraint(equalTo: topAnchor),
            ctaLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            ctaLabel.widthAnchor.constraint(equalToConstant: 96)
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
