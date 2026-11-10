//
//  SettingsViewController.swift
//  pass
//

import passKit
import SwiftUI

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
        model.refresh()
    }

    func alert(title: String, message: String) {
        Utils.alert(title: title, message: message, controller: self)
    }
}
