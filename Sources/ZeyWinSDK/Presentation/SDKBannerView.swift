import UIKit

@MainActor
final class SDKBannerView: UIView {

    private let content: SDKBannerContent

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.font = .preferredFont(
            forTextStyle: .headline
        )
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.font = .preferredFont(
            forTextStyle: .footnote
        )
        label.textColor = .secondaryLabel
        return label
    }()

    private let mediaImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = .tertiarySystemFill
        return imageView
    }()

    private let openButton: UIButton = {
        let button = UIButton(
            type: .system
        )
        button.setTitle(
            "Open",
            for: .normal
        )
        return button
    }()

    private let closeButton: UIButton = {
        let button = UIButton(
            type: .system
        )
        button.setTitle(
            "×",
            for: .normal
        )
        return button
    }()

    init(content: SDKBannerContent) {
        self.content = content
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.masksToBounds = true

        titleLabel.text = content.title
        bodyLabel.text = content.body
        bodyLabel.isHidden = content.body?.isEmpty ?? true
        openButton.setTitle(
            content.ctaText,
            for: .normal
        )

        mediaImageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        openButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mediaImageView)
        addSubview(titleLabel)
        addSubview(bodyLabel)
        addSubview(openButton)
        addSubview(closeButton)

        openButton.addTarget(
            self,
            action: #selector(openTapped),
            for: .touchUpInside
        )

        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )

        NSLayoutConstraint.activate([
            mediaImageView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 12
            ),
            mediaImageView.centerYAnchor.constraint(
                equalTo: centerYAnchor
            ),
            mediaImageView.widthAnchor.constraint(
                equalToConstant: 44
            ),
            mediaImageView.heightAnchor.constraint(
                equalToConstant: 44
            ),

            titleLabel.leadingAnchor.constraint(
                equalTo: mediaImageView.trailingAnchor,
                constant: 12
            ),
            titleLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 10
            ),

            bodyLabel.leadingAnchor.constraint(
                equalTo: titleLabel.leadingAnchor
            ),
            bodyLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 2
            ),
            bodyLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: bottomAnchor,
                constant: -10
            ),

            openButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: 12
            ),
            openButton.centerYAnchor.constraint(
                equalTo: centerYAnchor
            ),

            closeButton.leadingAnchor.constraint(
                equalTo: openButton.trailingAnchor,
                constant: 10
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -12
            ),
            closeButton.centerYAnchor.constraint(
                equalTo: centerYAnchor
            )
        ])

        loadMediaIfNeeded()
    }

    @objc
    private func openTapped() {
        SDKTrackingClient.shared.fire(
            content.tracking,
            event: "click"
        )

        UIApplication.shared.open(
            content.targetURL
        )
    }

    @objc
    private func closeTapped() {
        removeFromSuperview()
    }

    private func loadMediaIfNeeded() {
        guard let mediaURL = content.mediaURL else {
            mediaImageView.isHidden = true
            return
        }

        Task { [weak self] in
            do {
                let (
                    data,
                    _
                ) = try await URLSession.shared.data(
                    from: mediaURL
                )

                guard let image = UIImage(data: data) else {
                    return
                }

                await MainActor.run {
                    self?.mediaImageView.image = image
                }
            } catch {
                SDKLogger.log(
                    "Banner media load failed: \(error.localizedDescription)"
                )
            }
        }
    }
}
