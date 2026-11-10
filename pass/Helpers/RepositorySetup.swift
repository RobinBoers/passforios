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
        ProgressSheet.show("Cloning Remote Repository", on: self)
        // swiftlint:disable:next closure_body_length
        DispatchQueue.global(qos: .userInitiated).async {
            let passwordStore = PasswordStore.shared
            do {
                let transferProgressBlock: (UnsafePointer<git_transfer_progress>, UnsafeMutablePointer<ObjCBool>) -> Void = { git_transfer_progress, _ in
                    let gitTransferProgress = git_transfer_progress.pointee
                    let progress = Float(gitTransferProgress.received_objects) / Float(gitTransferProgress.total_objects)
                    DispatchQueue.main.async {
                        ProgressSheet.update(progress: progress, status: "Cloning Remote Repository")
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
        let alert = UIAlertController(title: "Done".localize(), message: "WantToSaveGitCredential?".localize(), preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: "No".localize(), style: .default) { _ in
                Defaults.isRememberGitCredentialPassphraseOn = false
                PasswordStore.shared.gitPassword = nil
                PasswordStore.shared.gitSSHPrivateKeyPassphrase = nil
                completion()
            }
        )
        alert.addAction(
            UIAlertAction(title: "Yes".localize(), style: .destructive) { _ in
                Defaults.isRememberGitCredentialPassphraseOn = true
                completion()
            }
        )
        present(alert, animated: true)
    }

    /// Pulls, then pushes any local commits.
    func syncRepository(completion: @escaping () -> Void = {}) {
        ProgressSheet.show("SyncingPasswordStore".localize(), on: self)
        let gitCredential = GitCredential.from(
            authenticationMethod: Defaults.gitAuthenticationMethod,
            userName: Defaults.gitUsername,
            keyStore: AppKeychain.shared
        )
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let pullOptions = gitCredential.getCredentialOptions(passwordProvider: self.present)
                try PasswordStore.shared.pullRepository(options: pullOptions) { git_transfer_progress, _ in
                    DispatchQueue.main.async {
                        ProgressSheet.update(progress: Float(git_transfer_progress.pointee.received_objects) / Float(git_transfer_progress.pointee.total_objects), status: "PullingFromRemoteRepository".localize())
                    }
                }
                if PasswordStore.shared.numberOfLocalCommits > 0 {
                    let pushOptions = gitCredential.getCredentialOptions(passwordProvider: self.present)
                    try PasswordStore.shared.pushRepository(options: pushOptions) { current, total, _, _ in
                        DispatchQueue.main.async {
                            ProgressSheet.update(progress: Float(current) / Float(total), status: "PushingToRemoteRepository".localize())
                        }
                    }
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .passwordStoreSyncSucceeded, object: nil)
                    ProgressSheet.dismiss {
                        Feedback.success()
                        completion()
                    }
                }
            } catch let error as NSError {
                gitCredential.delete()
                DispatchQueue.main.async {
                    var message = error.localizedDescription
                    if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                        message = message | "UnderlyingError".localize(underlyingError.localizedDescription)
                        if underlyingError.localizedDescription.contains("WrongPassphrase".localize()) {
                            message = message | "RecoverySuggestion.".localize()
                        }
                    }
                    if let mergeConflictFiles = error.userInfo[GTPullMergeConflictedFiles] as? NSArray {
                        let mergeConflictFilesString = mergeConflictFiles.componentsJoined(by: ", ")
                        message = message | "MergeConflictError".localize(mergeConflictFilesString)
                    }
                    Utils.alert(title: "Error".localize(), message: message, controller: self, completion: nil)
                }
            }
        }
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
        Defaults.gitSignatureName = name
        Defaults.gitSignatureEmail = email
    }

    /// Whether cloning needs a passphrase or password, which onboarding asks for on a screen of its own.
    var needsGitSecret: Bool {
        sshKey.map(SSHKey.isEncrypted) ?? true
    }
}
