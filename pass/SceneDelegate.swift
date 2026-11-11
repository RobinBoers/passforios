//
//  SceneDelegate.swift
//  pass
//

import passKit
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    enum ViewTag: Int {
        case blur = 100, appicon
    }

    var window: UIWindow?

    private var appLockPresenter: AppLockPresenter?

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        let passwords = UINavigationController(rootViewController: PasswordListViewController())
        passwords.navigationBar.prefersLargeTitles = true
        let window = UIWindow(windowScene: windowScene)
        // Before iOS 26 settings has a tab of its own; after, the password list opens it.
        if #available(iOS 26.0, *) {
            window.rootViewController = passwords
        } else {
            let settings = SettingsViewController()
            settings.tabBarItem = UITabBarItem(title: "Settings".localize(), image: UIImage(systemName: "gearshape"), selectedImage: UIImage(systemName: "gearshape.fill"))
            passwords.tabBarItem = UITabBarItem(title: "Passwords".localize(), image: UIImage(systemName: "key"), selectedImage: UIImage(systemName: "key.fill"))
            let tabBarController = UITabBarController()
            tabBarController.viewControllers = [passwords, settings]
            window.rootViewController = tabBarController
        }
        window.makeKeyAndVisible()
        self.window = window
        appLockPresenter = AppLockPresenter(windowScene: windowScene)
        appLockPresenter?.lockIfEnabled()
        presentOnboardingIfNeeded()
        if connectionOptions.shortcutItem?.type == Globals.bundleIdentifier + ".search" {
            perform(#selector(postSearchNotification), with: nil, afterDelay: 0.4)
        }
        if let url = connectionOptions.urlContexts.first?.url {
            DispatchQueue.main.async {
                self.open(url)
            }
        }
    }

    func scene(_: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.first.map { open($0.url) }
    }

    /// Verification codes to set up, from `otpauth` links; nothing to set them up in before onboarding.
    private func open(_ url: URL) {
        let root = window?.rootViewController
        let tabBarController = root as? UITabBarController
        guard url.scheme == Constants.OTPAUTH, PasswordStore.shared.repositoryExists(),
              let navigationController = (tabBarController?.viewControllers?.first ?? root) as? UINavigationController,
              let list = navigationController.viewControllers.first as? PasswordListViewController else {
            return
        }
        tabBarController?.selectedIndex = 0
        list.setUpOneTimeCode(url)
    }

    func windowScene(_: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let root = window?.rootViewController
        let tabBarController = root as? UITabBarController
        guard shortcutItem.type == Globals.bundleIdentifier + ".search",
              let navigationController = (tabBarController?.viewControllers?.first ?? root) as? UINavigationController else {
            completionHandler(false)
            return
        }
        root?.dismiss(animated: false)
        tabBarController?.selectedIndex = 0
        navigationController.popToRootViewController(animated: false)
        perform(#selector(postSearchNotification), with: nil, afterDelay: 0.4)
        completionHandler(true)
    }

    private func presentOnboardingIfNeeded() {
        guard !Defaults.isOnboarded, !PasswordStore.shared.repositoryExists() else {
            return
        }
        DispatchQueue.main.async {
            self.window?.rootViewController?.presentOnboarding(animated: false)
        }
    }

    @objc
    func postSearchNotification() {
        NotificationCenter.default.post(name: .passwordSearch, object: nil)
    }

    func sceneWillResignActive(_: UIScene) {
        guard let window else {
            return
        }

        // Display a blur effect view
        let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blurEffectView.frame = window.bounds
        blurEffectView.tag = ViewTag.blur.rawValue
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(blurEffectView)

        // Display the Pass icon in the middle of the screen
        let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? NSDictionary
        let primaryIconsDictionary = iconsDictionary?["CFBundlePrimaryIcon"] as? NSDictionary
        let iconFiles = primaryIconsDictionary?["CFBundleIconFiles"] as? NSArray
        if let iconName = iconFiles?.lastObject as? String, let appIcon = UIImage(named: iconName) {
            let appIconView = UIImageView(image: appIcon)
            appIconView.layer.cornerRadius = appIcon.size.height / 5
            appIconView.layer.masksToBounds = true
            appIconView.center = window.center
            appIconView.tag = ViewTag.appicon.rawValue
            window.addSubview(appIconView)
        }

        PersistenceController.shared.save()
    }

    func sceneDidEnterBackground(_: UIScene) {
        appLockPresenter?.lockIfEnabled()
    }

    func sceneDidBecomeActive(_: UIScene) {
        appLockPresenter?.authenticate()
        window?.viewWithTag(ViewTag.appicon.rawValue)?.removeFromSuperview()
        window?.viewWithTag(ViewTag.blur.rawValue)?.removeFromSuperview()
    }
}
