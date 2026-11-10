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
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationCenterDispatcher.shared
        registerNotificationCategories()
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
