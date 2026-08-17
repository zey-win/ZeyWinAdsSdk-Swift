import UIKit

@MainActor
final class SDKBannerView: UIView {

    private let content: SDKBannerContent

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.font = .preferredFont(
            forTextStyle: .body
        )
        return label
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

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        openButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
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
            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 14
            ),
            titleLabel.centerYAnchor.constraint(
                equalTo: centerYAnchor
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
    }

    @objc
    private func openTapped() {
        UIApplication.shared.open(
            content.targetURL
        )
    }

    @objc
    private func closeTapped() {
        removeFromSuperview()
    }
}
