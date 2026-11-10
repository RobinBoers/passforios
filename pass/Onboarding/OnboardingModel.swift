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
        case welcome, gitPassphrase, gpgPassphrase, autoFill, oneTimeCodes, appLock
    }

    weak var host: OnboardingViewController?

    @Published var step = Step.welcome
    @Published var isAutoFillEnabled = false
    @Published var isWorking = false
    @Published var error: String?

    private var passport: Passport?

    var usesSSHKey: Bool {
        Defaults.gitAuthenticationMethod == .key
    }

    func setUpFromComputer() {
        host?.scanPassport { [weak self] passport in
            self?.importKeys(from: passport)
        }
    }

    func setUpManually() {
        host?.finish(showingSettings: true)
    }

    private func importKeys(from passport: Passport) {
        guard let host else {
            return
        }
        self.passport = passport
        ProgressSheet.show("ImportingKeys".localize(), on: host)
        Task.detached(priority: .userInitiated) {
            let error: Error? = {
                do {
                    try passport.importKeys()
                    return nil
                } catch {
                    return error
                }
            }()
            await MainActor.run {
                ProgressSheet.dismiss {
                    if let error {
                        Utils.alert(title: "Error".localize(), message: error.localizedDescription, controller: host)
                    } else if passport.needsGitSecret {
                        self.go(to: .gitPassphrase)
                    } else {
                        self.clone(secret: "", remember: false)
                    }
                }
            }
        }
    }

    /// Clones with the passphrase or password from the screen, offering it once so a wrong one fails
    /// instead of prompting again.
    func clone(secret: String, remember: Bool) {
        guard let passport, let host else {
            return
        }
        Defaults.isRememberGitCredentialPassphraseOn = remember
        var offered = false
        let provider: GitCredential.PasswordProvider = { _, _ in
            defer { offered = true }
            return offered ? nil : secret
        }
        error = nil
        host.cloneRepository(
            url: passport.url,
            branch: passport.branch,
            username: passport.username ?? passport.url.user ?? "git",
            passwordProvider: provider,
            completion: { [weak self] in
                self?.go(to: .gpgPassphrase)
            },
            failure: { [weak self] message in
                self?.error = message
                self?.go(to: .gitPassphrase)
            }
        )
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
            go(to: .autoFill)
            return
        }
        isWorking = true
        error = nil
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
                self.isWorking = false
                if let error {
                    self.error = error.localizedDescription
                } else {
                    Feedback.success()
                    self.go(to: .autoFill)
                }
            }
        }
    }

    func go(to step: Step) {
        if step != self.step, step != .gitPassphrase {
            error = nil
        }
        withAnimation {
            self.step = step
        }
        if step == .autoFill {
            refreshAutoFillState()
        }
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in
            DispatchQueue.main.async {
                self.afterOneTimeCodes()
            }
        }
    }

    func afterOneTimeCodes() {
        if AppLock.isAvailable {
            go(to: .appLock)
        } else {
            finish()
        }
    }

    func turnOnAppLock() {
        AppLock.authenticate(reason: "TurnOnAppLock".localize()) { success in
            AppLock.isEnabled = success
            if success {
                self.finish()
            }
        }
    }

    func finish() {
        host?.finish(showingSettings: false)
    }
}
