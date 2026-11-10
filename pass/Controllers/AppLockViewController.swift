//
//  AppLockViewController.swift
//  pass
//

import passKit
import UIKit

/// Covers the app until the user authenticates.
final class AppLockViewController: UIViewController {
    var onUnlock: (() -> Void)?

    private var isAuthenticating = false
    private var hasPrompted = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .secondarySystemBackground

        let iconSize: CGFloat = 120
        let icon = UIImageView(image: #imageLiteral(resourceName: "Logo"))
        icon.layer.cornerRadius = iconSize * 0.225
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        icon.layer.borderWidth = 1 / 1.5
        icon.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
        lock.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: iconSize * 0.55, weight: .semibold)
        lock.tintColor = .systemGray
        lock.translatesAutoresizingMaskIntoConstraints = false

        // The lock hangs off the icon's corner, like on the system's locked apps.
        let image = UIView()
        image.addSubview(icon)
        image.addSubview(lock)
        image.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
            icon.topAnchor.constraint(equalTo: image.topAnchor),
            icon.bottomAnchor.constraint(equalTo: image.bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: image.leadingAnchor),
            icon.trailingAnchor.constraint(equalTo: image.trailingAnchor),
            lock.centerXAnchor.constraint(equalTo: icon.trailingAnchor, constant: iconSize * 0.01),
            lock.centerYAnchor.constraint(equalTo: icon.bottomAnchor, constant: -iconSize * 0.06),
        ])

        let title = UILabel()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
        title.text = "IsLocked(%@)".localize(appName)
        title.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 28, weight: .bold))
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.textAlignment = .center

        var configuration = UIButton.Configuration.gray()
        configuration.title = "Unlock".localize()
        configuration.baseForegroundColor = .tintColor
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .medium))
            return attributes
        }
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [unowned self] _ in
            authenticate()
        })

        let stack = UIStackView(arrangedSubviews: [image, title, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 32
        stack.setCustomSpacing(40, after: image)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: 4),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.readableContentGuide.trailingAnchor),
        ])
    }

    /// Prompts once by itself, as cancelling the prompt reactivates the scene; after that only the button does.
    func authenticateOnce() {
        guard !hasPrompted else {
            return
        }
        authenticate()
    }

    func authenticate() {
        guard !isAuthenticating else {
            return
        }
        isAuthenticating = true
        hasPrompted = true
        AppLock.authenticate(reason: "UnlockPass".localize()) { [weak self] success in
            self?.isAuthenticating = false
            if success {
                self?.onUnlock?()
            }
        }
    }
}

/// Shows the lock in a window of its own, above everything the app presents.
final class AppLockPresenter {
    private weak var windowScene: UIWindowScene?
    private var window: UIWindow?

    init(windowScene: UIWindowScene) {
        self.windowScene = windowScene
    }

    func lockIfEnabled() {
        guard AppLock.isEnabled, window == nil, let windowScene else {
            return
        }
        windowScene.windows.forEach { $0.endEditing(true) }
        let lock = AppLockViewController()
        lock.onUnlock = { [weak self] in
            self?.window?.isHidden = true
            self?.window = nil
            self?.windowScene?.windows.first?.makeKey()
        }
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1
        window.rootViewController = lock
        window.makeKeyAndVisible()
        self.window = window
    }

    func authenticate() {
        (window?.rootViewController as? AppLockViewController)?.authenticateOnce()
    }
}
