//
//  OnboardingViewController.swift
//  pass
//

import passKit
import SwiftUI

extension UIViewController {
    /// Shows onboarding; setting up manually ends in Settings.
    func presentOnboarding(animated: Bool = true) {
        let onboarding = OnboardingViewController { [weak self] showingSettings in
            if showingSettings {
                self?.presentSettings()
            }
        }
        topmostPresentedViewController.present(onboarding, animated: animated)
    }
}

final class OnboardingViewController: UIHostingController<AnyView>, PasswordAlertPresenter {
    private let model: OnboardingModel
    private let onFinish: (_ showingSettings: Bool) -> Void

    /// With a code scanned before, setting up continues from it in a sheet instead of starting over.
    init(passport: Passport? = nil, onFinish: @escaping (_ showingSettings: Bool) -> Void) {
        let model = OnboardingModel(passport: passport)
        self.model = model
        self.onFinish = onFinish
        super.init(rootView: AnyView(OnboardingView().environmentObject(model)))
        model.host = self
        modalPresentationStyle = passport == nil ? .fullScreen : .pageSheet
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
