//
//  AppDelegate.swift
//  pass
//
//  Created by Mingshen Sun on 18/1/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import passKit
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    private var badgeObservers = [NSObjectProtocol]()

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationCenterDispatcher.shared
        registerNotificationCategories()
        badgeObservers = [Notification.Name.passwordStoreUpdated, .passwordStoreSyncSucceeded, .passwordStoreChangeDiscarded, .passwordStoreErased].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                AppBadge.update()
            }
        }
        AppBadge.update()
        return true
    }

    private func registerNotificationCategories() {
        let notificationCenter = UNUserNotificationCenter.current()

        // Register notification action
        let copyAction = UNNotificationAction(
            identifier: Globals.otpNotificationCopyAction,
            title: "CopyToPasteboard".localize(),
            options: UNNotificationActionOptions(rawValue: 0)
        )
        let otpCategory = UNNotificationCategory(
            identifier: Globals.otpNotificationCategory,
            actions: [copyAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "",
            options: []
        )
        notificationCenter.setNotificationCategories([otpCategory])
    }

    func applicationWillTerminate(_: UIApplication) {
        // Saves changes in the application's managed object context before the application terminates.
        PersistenceController.shared.save()
    }
}

/// Shows how many commits wait to be pushed on the app icon, like the sync button does.
enum AppBadge {
    static func update() {
        let count = PasswordStore.shared.numberOfLocalCommits
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            // Not asked for during onboarding, the first change waiting to be pushed is when a badge starts to
            // matter. Alerts are asked for along with it, as there is only one chance to ask.
            let shouldAsk = settings.authorizationStatus == .notDetermined && count > 0
                || settings.authorizationStatus == .authorized && settings.badgeSetting == .notSupported
            guard shouldAsk else {
                center.setBadgeCount(count)
                return
            }
            center.requestAuthorization(options: [.alert, .badge]) { _, _ in
                center.setBadgeCount(count)
            }
        }
    }
}
