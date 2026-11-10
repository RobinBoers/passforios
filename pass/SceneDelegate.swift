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
        if let tabBarController = window?.rootViewController as? UITabBarController {
            configureTabs(of: tabBarController)
        }
        appLockPresenter = AppLockPresenter(windowScene: windowScene)
        appLockPresenter?.lockIfEnabled()
        presentOnboardingIfNeeded()
        if connectionOptions.shortcutItem?.type == Globals.bundleIdentifier + ".search" {
            perform(#selector(postSearchNotification), with: nil, afterDelay: 0.4)
        }
    }

    func windowScene(_: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard shortcutItem.type == Globals.bundleIdentifier + ".search",
              let tabBarController = window?.rootViewController as? UITabBarController else {
            completionHandler(false)
            return
        }
        tabBarController.selectedIndex = 0
        (tabBarController.selectedViewController as? UINavigationController)?.popToRootViewController(animated: false)
        perform(#selector(postSearchNotification), with: nil, afterDelay: 0.4)
        completionHandler(true)
    }

    /// Passwords and Settings, plus a search tab where the system has one, which puts search at the bottom.
    private func configureTabs(of tabBarController: UITabBarController) {
        let settings = SettingsViewController()
        settings.tabBarItem = UITabBarItem(title: "Settings".localize(), image: UIImage(systemName: "gearshape"), selectedImage: UIImage(systemName: "gearshape.fill"))
        guard #available(iOS 18.0, *),
              let passwords = tabBarController.viewControllers?.first,
              let search = tabBarController.storyboard?.instantiateViewController(withIdentifier: "passwordNavigation") as? PasswordNavigationViewController else {
            tabBarController.viewControllers = (tabBarController.viewControllers ?? []) + [settings]
            return
        }
        search.isSearchTab = true
        let searchTab = UISearchTab { _ in
            UINavigationController(rootViewController: search)
        }
        if #available(iOS 26.0, *) {
            searchTab.automaticallyActivatesSearch = true
        }
        tabBarController.tabs = [
            UITab(title: "Passwords".localize(), image: UIImage(systemName: "key.fill"), identifier: "passwords") { _ in passwords },
            UITab(title: "Settings".localize(), image: UIImage(systemName: "gearshape"), identifier: "settings") { _ in settings },
            searchTab,
        ]
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
