//
//  OnboardingModel.swift
//  pass
//

import AuthenticationServices
import passKit
import SwiftUI
import UserNotifications

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step {
        case welcome, passphrase, autoFill
    }

    weak var host: OnboardingViewController?

    @Published var step = Step.welcome
    @Published var isAutoFillEnabled = false
    @Published var isVerifying = false
    @Published var passphraseError: String?

    func setUpFromComputer() {
        host?.setUpFromComputer { [weak self] in
            withAnimation {
                self?.step = .passphrase
            }
        }
    }

    func setUpManually() {
        host?.finish(showingSettings: true)
    }

    /// Decrypts one entry with the passphrase, so a typo shows up now instead of in AutoFill later.
    func verify(passphrase: String, remember: Bool) {
        Defaults.isRememberPGPPassphraseOn = remember
        let requestPassphrase: (String) -> String = { keyID in
            if remember {
                AppKeychain.shared.add(string: passphrase, for: AppKeychain.getPGPKeyPassphraseKey(keyID: keyID))
            }
            return passphrase
        }
        guard let path = PasswordStore.shared.fetchPasswordEntityCoreData(withDir: false).first?.path else {
            _ = requestPassphrase("")
            next()
            return
        }
        isVerifying = true
        passphraseError = nil
        Task.detached(priority: .userInitiated) {
            let error: Error? = {
                do {
                    _ = try PasswordStore.shared.decrypt(path: path, requestPGPKeyPassphrase: requestPassphrase)
                    return nil
                } catch {
                    AppKeychain.shared.removeAllContent(withPrefix: Globals.pgpKeyPassphrase)
                    return error
                }
            }()
            await MainActor.run {
                self.isVerifying = false
                if let error {
                    self.passphraseError = error.localizedDescription
                } else {
                    Feedback.success()
                    self.next()
                }
            }
        }
    }

    func next() {
        withAnimation {
            step = .autoFill
        }
        refreshAutoFillState()
    }

    func refreshAutoFillState() {
        ASCredentialIdentityStore.shared.getState { state in
            DispatchQueue.main.async {
                self.isAutoFillEnabled = state.isEnabled
            }
        }
    }

    func turnOnAutoFill() {
        if #available(iOS 18.0, *) {
            ASSettingsHelper.requestToTurnOnCredentialProviderExtension { _ in
                DispatchQueue.main.async {
                    self.refreshAutoFillState()
                }
            }
        } else if #available(iOS 17.0, *) {
            ASSettingsHelper.openCredentialProviderAppSettings()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// One-time codes are shown in a notification after AutoFill fills in a password.
    func allowOneTimeCodeNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    var appLock: Binding<Bool> {
        Binding {
            AppLock.isEnabled
        } set: { [weak self] isOn in
            guard isOn else {
                AppLock.isEnabled = false
                self?.objectWillChange.send()
                return
            }
            AppLock.authenticate(reason: "TurnOnAppLock".localize()) { success in
                AppLock.isEnabled = success
                self?.objectWillChange.send()
            }
        }
    }

    func finish() {
        host?.finish(showingSettings: false)
    }
}
