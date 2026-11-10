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
        case welcome, importing, gitPassphrase, gpgPassphrase, autoFill, oneTimeCodes, appLock
    }

    weak var host: OnboardingViewController?

    /// Welcome on the first run; importing for a code scanned elsewhere, until the next step takes its place.
    @Published var root: Step
    @Published var path = [Step]()
    @Published var isAutoFillEnabled = false
    @Published var isWorking = false
    @Published var error: String?

    private var passport: Passport?

    /// Starts with a code scanned before, or else with the welcome.
    init(passport: Passport? = nil) {
        self.passport = passport
        self.root = passport == nil ? .welcome : .importing
    }

    var step: Step {
        path.last ?? root
    }

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

    func importScannedKeys() {
        if let passport {
            importKeys(from: passport)
        }
    }

    private func importKeys(from passport: Passport) {
        guard let host else {
            return
        }
        self.passport = passport
        // The importing step shows progress itself.
        let showsProgress = root != .importing
        if showsProgress {
            ProgressSheet.show("ImportingKeys".localize(), on: host)
        }
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
                let next = {
                    if let error {
                        self.fail(title: "Error".localize(), message: error.localizedDescription)
                    } else if passport.needsGitSecret {
                        self.go(to: .gitPassphrase)
                    } else {
                        self.clone(secret: "", remember: false)
                    }
                }
                if showsProgress {
                    ProgressSheet.dismiss(completion: next)
                } else {
                    next()
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
                guard let self else {
                    return
                }
                guard passport.needsGitSecret else {
                    fail(title: "CouldNotClone".localize(), message: message)
                    return
                }
                error = message
                if step != .gitPassphrase {
                    go(to: .gitPassphrase)
                }
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

    /// Shows an error; with nothing behind it to go back to, it ends setting up.
    private func fail(title: String, message: String) {
        guard let host else {
            return
        }
        Utils.alert(title: title, message: message, controller: host) { _ in
            if self.root == .importing {
                self.cancel()
            }
        }
    }

    func go(to step: Step) {
        if step != .gitPassphrase {
            error = nil
        }
        if root == .importing {
            withAnimation {
                root = step
            }
        } else {
            path.append(step)
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

    func cancel() {
        finish()
    }
}
