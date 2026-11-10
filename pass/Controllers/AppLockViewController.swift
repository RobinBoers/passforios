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

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blur.frame = view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blur)

        let image = UIImageView(image: UIImage(systemName: "lock.fill"))
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle, scale: .large)
        image.tintColor = .secondaryLabel

        let title = UILabel()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
        title.text = "IsLocked(%@)".localize(appName)
        title.font = .preferredFont(forTextStyle: .title2, compatibleWith: UITraitCollection(legibilityWeight: .bold))
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.textAlignment = .center

        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .prominentGlass()
        } else {
            configuration = .borderedProminent()
            configuration.cornerStyle = .capsule
        }
        configuration.title = "UseMethod(%@)".localize(AppLock.methodName)
        configuration.image = UIImage(systemName: AppLock.symbolName)
        configuration.imagePadding = 8
        configuration.buttonSize = .large
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [unowned self] _ in
            authenticate()
        })

        let stack = UIStackView(arrangedSubviews: [image, title, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(32, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
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
