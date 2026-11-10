//
//  SettingsModel.swift
//  pass
//

import passKit
import SwiftUI
import SwiftyUserDefaults

/// The settings' state, and their bridge to the UIKit flows for cloning and setting up from a computer.
@MainActor
final class SettingsModel: ObservableObject {
    struct StoreInfo {
        var passwords = 0
        var size: Int64 = 0
        var commits: Int?
        var localCommits = 0
        var lastSynced: Date?
    }

    weak var host: SettingsViewController?

    @Published var storeInfo = StoreInfo()
    @Published var pgpKeyIDs = [String]()
    @Published var hasSSHKey = false
    @Published var hasStore = false

    private var observers = [NSObjectProtocol]()

    init() {
        for name in [Notification.Name.passwordStoreUpdated, .passwordStoreErased] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            })
        }
        refresh()
    }

    func refresh() {
        let store = PasswordStore.shared
        hasStore = store.repositoryExists()
        pgpKeyIDs = (try? PGPAgent.shared.getShortKeyID()) ?? []
        hasSSHKey = AppKeychain.shared.contains(key: SSHKey.PRIVATE.getKeychainKey())
        Task.detached(priority: .userInitiated) {
            let info = StoreInfo(
                passwords: store.numberOfPasswords,
                size: Int64(store.sizeOfRepositoryByteCount),
                commits: store.numberOfCommits,
                localCommits: store.numberOfLocalCommits,
                lastSynced: store.lastSyncedTime
            )
            await MainActor.run {
                self.storeInfo = info
            }
        }
    }

    // MARK: - Preferences

    func binding(_ key: KeyPath<DefaultsKeys, DefaultsKey<Bool>>, didSet: ((Bool) -> Void)? = nil) -> Binding<Bool> {
        Binding {
            passKit.Defaults[key]
        } set: { [weak self] value in
            passKit.Defaults[key] = value
            didSet?(value)
            self?.objectWillChange.send()
        }
    }

    var rememberPGPPassphrase: Binding<Bool> {
        binding(\.isRememberPGPPassphraseOn) { isOn in
            if !isOn {
                AppKeychain.shared.removeAllContent(withPrefix: Globals.pgpKeyPassphrase)
            }
        }
    }

    var rememberGitCredential: Binding<Bool> {
        binding(\.isRememberGitCredentialPassphraseOn) { isOn in
            if !isOn {
                PasswordStore.shared.gitSSHPrivateKeyPassphrase = nil
                PasswordStore.shared.gitPassword = nil
            }
        }
    }

    var autoCopyOTP: Binding<Bool> {
        binding(\.autoCopyOTP)
    }

    var showFolders: Binding<Bool> {
        binding(\.isShowFolderOn) { _ in
            NotificationCenter.default.post(name: .passwordDisplaySettingChanged, object: nil)
        }
    }

    /// Turning the lock on asks for authentication first, so nobody locks themselves out.
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

    var signatureName: Binding<String> {
        Binding { passKit.Defaults.gitSignatureName ?? "" } set: { passKit.Defaults.gitSignatureName = $0.isEmpty ? nil : $0 }
    }

    var signatureEmail: Binding<String> {
        Binding { passKit.Defaults.gitSignatureEmail ?? "" } set: { passKit.Defaults.gitSignatureEmail = $0.isEmpty ? nil : $0 }
    }

    // MARK: - Actions

    func setUpFromComputer() {
        host?.setUpFromComputer { [weak self] in
            self?.refresh()
        }
    }

    func clone(url: URL, branch: String, username: String, authentication: GitAuthenticationMethod) {
        passKit.Defaults.gitAuthenticationMethod = authentication
        host?.cloneRepository(url: url, branch: branch, username: username) { [weak self] in
            self?.refresh()
        }
    }

    func importPGPKey(_ armor: String) throws {
        AppKeychain.shared.removeAllContent(withPrefix: Globals.pgpKeyPassphrase)
        // The private key carries its public half, which is all encryption needs.
        try KeyFileManager.PublicPGP.importKey(from: armor)
        try KeyFileManager.PrivatePGP.importKey(from: armor)
        try PGPAgent.shared.initKeys()
        passKit.Defaults.pgpKeySource = .armor
        refresh()
    }

    func removePGPKey() {
        AppKeychain.shared.removeContent(for: PGPKey.PUBLIC.getKeychainKey())
        AppKeychain.shared.removeContent(for: PGPKey.PRIVATE.getKeychainKey())
        AppKeychain.shared.removeAllContent(withPrefix: Globals.pgpKeyPassphrase)
        PGPAgent.shared.uninitKeys()
        passKit.Defaults.pgpKeySource = nil
        refresh()
    }

    func importSSHKey(_ armor: String) throws {
        try KeyFileManager.PrivateSSH.importKey(from: armor)
        PasswordStore.shared.gitSSHPrivateKeyPassphrase = nil
        passKit.Defaults.gitSSHKeySource = .armor
        passKit.Defaults.gitAuthenticationMethod = .key
        refresh()
    }

    func removeSSHKey() {
        PasswordStore.shared.removeGitSSHKeys()
        passKit.Defaults.gitSSHKeySource = nil
        passKit.Defaults.gitAuthenticationMethod = .password
        refresh()
    }

    func clearSuggestions() {
        CredentialIdentities.removeAll { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.host?.alert(title: "Error".localize(), message: "FailedToClearQuickTypeSuggestions".localize(error))
                } else {
                    Feedback.success()
                }
            }
        }
    }

    func discardLocalChanges() {
        do {
            let discarded = try PasswordStore.shared.reset()
            host?.alert(title: "Done".localize(), message: "DiscardedCommits(%d)".localize(discarded))
        } catch {
            host?.alert(title: "Error".localize(), message: error.localizedDescription)
        }
        refresh()
    }

    func erase() {
        PasswordStore.shared.erase()
        Feedback.success()
        refresh()
    }
}
