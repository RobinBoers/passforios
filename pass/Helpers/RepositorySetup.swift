//
//  RepositorySetup.swift
//  pass
//

import ObjectiveGit
import passKit
import UIKit

extension PasswordAlertPresenter where Self: UIViewController {
    /// Clones the store. Without a password provider, the passphrase is asked for in an alert and the user is
    /// asked afterwards whether to remember it. With a failure handler, errors go there instead of an alert.
    func cloneRepository(
        url: URL,
        branch: String,
        username: String,
        passwordProvider: GitCredential.PasswordProvider? = nil,
        completion: @escaping () -> Void,
        failure: ((String) -> Void)? = nil
    ) {
        // A remembered password belongs to an account on a host; the SSH passphrase to the key, which
        // stays the same.
        if url.gitHost != Defaults.gitURL.gitHost || username != Defaults.gitUsername {
            PasswordStore.shared.gitPassword = nil
        }
        Defaults.gitURL = url
        Defaults.gitBranchName = branch
        Defaults.gitUsername = username

        if passwordProvider == nil {
            // Remember git credential password/passphrase temporarily, ask whether users want this after a successful clone.
            Defaults.isRememberGitCredentialPassphraseOn = true
        }
        let fail: (String) -> Void = { message in
            if let failure {
                ProgressSheet.dismiss {
                    failure(message)
                }
            } else {
                Utils.alert(title: "Error".localize(), message: message, controller: self)
            }
        }
        ProgressSheet.show("CloningStore".localize(), on: self)
        // swiftlint:disable:next closure_body_length
        DispatchQueue.global(qos: .userInitiated).async {
            let passwordStore = PasswordStore.shared
            do {
                let transferProgressBlock: (UnsafePointer<git_transfer_progress>, UnsafeMutablePointer<ObjCBool>) -> Void = { git_transfer_progress, _ in
                    let gitTransferProgress = git_transfer_progress.pointee
                    let progress = Float(gitTransferProgress.received_objects) / Float(gitTransferProgress.total_objects)
                    DispatchQueue.main.async {
                        ProgressSheet.update(progress: progress, status: "CloningStore".localize())
                    }
                }

                let checkoutProgressBlock: (String, UInt, UInt) -> Void = { _, completedSteps, totalSteps in
                    let progress = Float(completedSteps) / Float(totalSteps)
                    DispatchQueue.main.async {
                        ProgressSheet.update(progress: progress, status: "CheckingOutBranch".localize(branch))
                    }
                }

                let gitCredential = GitCredential.from(
                    authenticationMethod: Defaults.gitAuthenticationMethod,
                    userName: username,
                    keyStore: AppKeychain.shared
                )

                try passwordStore.cloneRepository(
                    remoteRepoURL: url,
                    branchName: branch,
                    options: gitCredential.getCredentialOptions(passwordProvider: passwordProvider ?? self.present),
                    transferProgressBlock: transferProgressBlock,
                    checkoutProgressBlock: checkoutProgressBlock
                )

                let gpgIDFile = passwordStore.storeURL.appendingPathComponent(".gpg-id").path
                guard FileManager.default.fileExists(atPath: gpgIDFile) else {
                    passwordStore.eraseStoreData()
                    DispatchQueue.main.async {
                        fail("NoProperPassRepo.".localize())
                    }
                    return
                }

                DispatchQueue.main.async {
                    ProgressSheet.dismiss {
                        if passwordProvider == nil {
                            self.askToRememberGitCredential(completion: completion)
                        } else {
                            completion()
                        }
                    }
                }
            } catch {
                passwordStore.eraseStoreData()
                let error = error as NSError
                var message = error.localizedDescription
                if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                    message = "\(message)\n\("UnderlyingError".localize(underlyingError.localizedDescription))"
                }
                DispatchQueue.main.async {
                    fail(message)
                }
            }
        }
    }

    private func askToRememberGitCredential(completion: @escaping () -> Void) {
        let title = Defaults.gitAuthenticationMethod == .key ? "RememberSshPassphrase?" : "RememberGitPassword?"
        let alert = UIAlertController(title: title.localize(), message: "RememberGitSecret.".localize(), preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: "NotNow".localize(), style: .default) { _ in
                Defaults.isRememberGitCredentialPassphraseOn = false
                PasswordStore.shared.gitPassword = nil
                PasswordStore.shared.gitSSHPrivateKeyPassphrase = nil
                completion()
            }
        )
        alert.addAction(
            UIAlertAction(title: "Remember".localize(), style: .default) { _ in
                Defaults.isRememberGitCredentialPassphraseOn = true
                completion()
            }
        )
        alert.preferredAction = alert.actions.last
        present(alert, animated: true)
    }

    /// Pulls, then pushes any local commits. Progress goes to `status` when given, for showing it inline,
    /// and to a progress sheet otherwise. `completion` runs either way, telling whether the sync succeeded.
    /// A sync that is not interactive asks for nothing and reports failure only through `completion`.
    func syncRepository(interactive: Bool = true, status: ((String) -> Void)? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        let report: (Float, String) -> Void = { progress, message in
            DispatchQueue.main.async {
                if let status {
                    status(progress.isFinite ? "\(message) \(Int(progress * 100))%" : message)
                } else {
                    ProgressSheet.update(progress: progress, status: message)
                }
            }
        }
        if let status {
            status("SyncingPasswordStore".localize())
        } else {
            ProgressSheet.show("SyncingPasswordStore".localize(), on: self)
        }
        let gitCredential = GitCredential.from(
            authenticationMethod: Defaults.gitAuthenticationMethod,
            userName: Defaults.gitUsername,
            keyStore: AppKeychain.shared
        )
        // Without asking, only a key that has no passphrase can do without a remembered one.
        let passwordProvider: GitCredential.PasswordProvider = interactive ? present : { _, _ in
            let key: String? = AppKeychain.shared.get(for: SSHKey.PRIVATE.getKeychainKey())
            return Defaults.gitAuthenticationMethod == .key && key.map(SSHKey.isEncrypted) == false ? "" : nil
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let pullOptions = gitCredential.getCredentialOptions(passwordProvider: passwordProvider)
                try PasswordStore.shared.pullRepository(options: pullOptions) { git_transfer_progress, _ in
                    report(Float(git_transfer_progress.pointee.received_objects) / Float(git_transfer_progress.pointee.total_objects), "PullingFromRemoteRepository".localize())
                }
                if PasswordStore.shared.numberOfLocalCommits > 0 {
                    let pushOptions = gitCredential.getCredentialOptions(passwordProvider: passwordProvider)
                    try PasswordStore.shared.pushRepository(options: pushOptions) { current, total, _, _ in
                        report(Float(current) / Float(total), "PushingToRemoteRepository".localize())
                    }
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .passwordStoreSyncSucceeded, object: nil)
                    ProgressSheet.dismiss {
                        completion(true)
                    }
                }
            } catch let error as NSError {
                guard interactive else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                gitCredential.delete()
                DispatchQueue.main.async {
                    completion(false)
                    Feedback.error()
                    Utils.alert(title: "SyncFailed".localize(), message: Self.syncErrorMessage(error), controller: self, completion: nil)
                }
            }
        }
    }

    private static func syncErrorMessage(_ error: NSError) -> String {
        var message = error.localizedDescription
        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            message = message | "UnderlyingError".localize(underlyingError.localizedDescription)
            if underlyingError.localizedDescription.contains("WrongPassphrase".localize()) {
                message = message | "RecoverySuggestion.".localize()
            }
        }
        if let mergeConflictFiles = error.userInfo[GTPullMergeConflictedFiles] as? NSArray {
            message = message | "MergeConflictError".localize(mergeConflictFiles.componentsJoined(by: ", "))
        }
        return message
    }

    /// Scans the code shown by `passport` on a computer, confirming first when it would replace a store.
    func scanPassport(then handle: @escaping (Passport) -> Void) {
        let scanner = PassportScannerController()
        scanner.onScan = { passport in
            self.confirmOverwrite {
                handle(passport)
            }
        }
        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak scanner] _ in
            scanner?.dismiss(animated: true)
        })
        topmostPresentedViewController.present(UINavigationController(rootViewController: scanner), animated: true)
    }

    private func confirmOverwrite(then action: @escaping () -> Void) {
        guard PasswordStore.shared.repositoryExists() else {
            action()
            return
        }
        let alert = UIAlertController(title: "Overwrite?".localize(), message: "OperationWillOverwriteData.".localize(), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Overwrite".localize(), style: .destructive) { _ in action() })
        alert.addAction(UIAlertAction.cancel())
        topmostPresentedViewController.present(alert, animated: true)
    }
}

/// Git also takes `user@host:path` remotes, which Foundation parses without a host or path.
extension URL {
    private var scpLike: (host: Substring, path: Substring)? {
        guard host == nil, let remote = absoluteString.split(separator: "@").last, let colon = remote.firstIndex(of: ":") else {
            return nil
        }
        return (remote[..<colon], remote[remote.index(after: colon)...])
    }

    var gitHost: String {
        host ?? scpLike.map { String($0.host) } ?? absoluteString
    }

    /// The repository's path on its host, like `meta/passwords`.
    var gitPath: String {
        var path = scpLike.map { String($0.path) } ?? path
        for prefix in ["/~/", "/", "~/"] where path.hasPrefix(prefix) {
            path.removeFirst(prefix.count)
            break
        }
        return path.hasSuffix(".git") ? String(path.dropLast(4)) : path
    }
}

extension Passport {
    func importKeys() throws {
        try PGPAgent.shared.importKeys(privateKey: pgpKey, otherPublicKeys: recipientKeys)

        PasswordStore.shared.gitPassword = nil
        PasswordStore.shared.gitSSHPrivateKeyPassphrase = nil
        if let sshKey {
            try KeyFileManager.PrivateSSH.importKey(from: sshKey)
            Defaults.gitSSHKeySource = .armor
            Defaults.gitAuthenticationMethod = .key
        } else {
            Defaults.gitAuthenticationMethod = .password
        }

        Defaults.storeFormat = format
        Defaults.protos = protos
        Defaults.gitSignatureName = name
        Defaults.gitSignatureEmail = email
    }

    /// Whether cloning needs a passphrase or password, which onboarding asks for on a screen of its own.
    var needsGitSecret: Bool {
        sshKey.map(SSHKey.isEncrypted) ?? true
    }
}
