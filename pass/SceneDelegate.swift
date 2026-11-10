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
        appLockPresenter = AppLockPresenter(windowScene: windowScene)
        appLockPresenter?.lockIfEnabled()
        presentOnboardingIfNeeded()
        if connectionOptions.shortcutItem?.type == Globals.bundleIdentifier + ".search" {
            perform(#selector(postSearchNotification), with: nil, afterDelay: 0.4)
        }
    }

    func windowScene(_: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard shortcutItem.type == Globals.bundleIdentifier + ".search",
              let navigationController = window?.rootViewController as? UINavigationController else {
            completionHandler(false)
            return
        }
        navigationController.dismiss(animated: false)
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
