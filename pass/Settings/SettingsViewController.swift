//
//  SettingsViewController.swift
//  pass
//

import passKit
import SwiftUI

extension UIViewController {
    /// Shows Settings: its tab where there is one, else a sheet, unless it is already showing.
    func presentSettings() {
        if let tabBarController = view.window?.rootViewController as? UITabBarController,
           let settings = tabBarController.viewControllers?.first(where: { $0 is SettingsViewController }) {
            tabBarController.dismiss(animated: true)
            tabBarController.selectedViewController = settings
            return
        }
        var controller: UIViewController? = view.window?.rootViewController ?? self
        while let current = controller {
            if current is SettingsViewController {
                return
            }
            controller = current.presentedViewController
        }
        topmostPresentedViewController.present(SettingsViewController(), animated: true)
    }
}

final class SettingsViewController: UIHostingController<AnyView>, PasswordAlertPresenter {
    private let model: SettingsModel

    init() {
        let model = SettingsModel()
        self.model = model
        super.init(rootView: AnyView(SettingsView().environmentObject(model)))
        model.host = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.isPresented = presentingViewController != nil
        model.refresh()
    }

    func close() {
        dismiss(animated: true)
    }

    /// Sets up from the start, as after erasing there is nothing left to show.
    func startOver() {
        guard presentingViewController != nil, let root = view.window?.rootViewController else {
            presentOnboarding()
            return
        }
        dismiss(animated: true) {
            root.presentOnboarding()
        }
    }

    func alert(title: String, message: String) {
        Utils.alert(title: title, message: message, controller: self)
    }
}
