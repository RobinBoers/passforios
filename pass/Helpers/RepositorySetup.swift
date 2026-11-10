//
//  RepositorySetup.swift
//  pass
//

import passKit
import UIKit

extension PasswordAlertPresenter where Self: UIViewController {
    func cloneRepository(url: URL, branch: String, username: String, completion: @escaping () -> Void) {
        Defaults.gitURL = url
        Defaults.gitBranchName = branch
        Defaults.gitUsername = username

        // Remember git credential password/passphrase temporarily, ask whether users want this after a successful clone.
        Defaults.isRememberGitCredentialPassphraseOn = true
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
                    options: gitCredential.getCredentialOptions(passwordProvider: self.present),
                    transferProgressBlock: transferProgressBlock,
                    checkoutProgressBlock: checkoutProgressBlock
                )

                let gpgIDFile = passwordStore.storeURL.appendingPathComponent(".gpg-id").path
                guard FileManager.default.fileExists(atPath: gpgIDFile) else {
                    passwordStore.eraseStoreData()
                    DispatchQueue.main.async {
                        Utils.alert(title: "Error".localize(), message: "NoProperPassRepo.".localize(), controller: self)
                    }
                    return
                }

                DispatchQueue.main.async {
                    ProgressSheet.dismiss {
                        self.askToRememberGitCredential(completion: completion)
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
                    Utils.alert(title: "Error".localize(), message: message, controller: self)
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

    /// Scans the code shown by `passport` on a computer, then imports its keys and clones its repository.
    func setUpFromComputer(completion: @escaping () -> Void = {}) {
        let scanner = PassportScannerController()
        scanner.onScan = { passport in
            self.confirmOverwrite {
                self.setUp(from: passport, completion: completion)
            }
        }
        navigationController?.pushViewController(scanner, animated: true)
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

    private func setUp(from passport: Passport, completion: @escaping () -> Void) {
        ProgressSheet.show("ImportingKeys".localize(), on: self)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try passport.importKeys()
                DispatchQueue.main.async {
                    self.cloneRepository(url: passport.url, branch: passport.branch, username: passport.username ?? passport.url.user ?? "git", completion: completion)
                }
            } catch {
                DispatchQueue.main.async {
                    Utils.alert(title: "Error".localize(), message: error.localizedDescription, controller: self)
                }
            }
        }
    }
}

private extension Passport {
    func importKeys() throws {
        AppKeychain.shared.removeAllContent(withPrefix: Globals.pgpKeyPassphrase)
        // The private key carries its public half, which is all encryption needs.
        try KeyFileManager.PublicPGP.importKey(from: pgpKey)
        try KeyFileManager.PrivatePGP.importKey(from: pgpKey)
        try PGPAgent.shared.initKeys()
        Defaults.pgpKeySource = .armor

        PasswordStore.shared.gitPassword = nil
        PasswordStore.shared.gitSSHPrivateKeyPassphrase = nil
        if let sshKey {
            try KeyFileManager.PrivateSSH.importKey(from: sshKey)
            Defaults.gitSSHKeySource = .armor
            Defaults.gitAuthenticationMethod = .key
        } else {
            Defaults.gitAuthenticationMethod = .password
        }

        Defaults.gitSignatureName = name
        Defaults.gitSignatureEmail = email
    }
}
