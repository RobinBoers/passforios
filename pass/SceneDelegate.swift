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

    lazy var passcodeLockPresenter = PasscodeLockPresenter(mainWindow: window)

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard scene is UIWindowScene else {
            return
        }
        passcodeLockPresenter.present(windowLevel: window?.windowLevel.rawValue)
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

    func sceneWillEnterForeground(_: UIScene) {
        passcodeLockPresenter.present(windowLevel: window?.windowLevel.rawValue)
    }

    func sceneDidBecomeActive(_: UIScene) {
        window?.viewWithTag(ViewTag.appicon.rawValue)?.removeFromSuperview()
        window?.viewWithTag(ViewTag.blur.rawValue)?.removeFromSuperview()
    }
}
