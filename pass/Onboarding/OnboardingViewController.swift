//
//  OnboardingViewController.swift
//  pass
//

import passKit
import SwiftUI

final class OnboardingViewController: UIHostingController<AnyView>, PasswordAlertPresenter {
    private let model: OnboardingModel
    private let onFinish: (_ showingSettings: Bool) -> Void

    init(onFinish: @escaping (_ showingSettings: Bool) -> Void) {
        let model = OnboardingModel()
        self.model = model
        self.onFinish = onFinish
        super.init(rootView: AnyView(OnboardingView().environmentObject(model)))
        model.host = self
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAutoFillState), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc
    private func refreshAutoFillState() {
        model.refreshAutoFillState()
    }

    func finish(showingSettings: Bool) {
        Defaults.isOnboarded = true
        dismiss(animated: true) {
            self.onFinish(showingSettings)
        }
    }
}
