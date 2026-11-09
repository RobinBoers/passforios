//
//  CredentialProviderViewController.swift
//  passAutoFillExtension
//
//  Created by Yishi Lin on 2018/9/24.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

import AuthenticationServices
import passKit

class CredentialProviderViewController: ASCredentialProviderViewController {
    private lazy var passcodelock: PasscodeExtensionDisplay = { [unowned self] in
        PasscodeExtensionDisplay(extensionContext: extensionContext)
    }()

    private lazy var passwordsViewController: PasswordsViewController = (children.first as! UINavigationController).viewControllers.first as! PasswordsViewController

    private lazy var credentialProvider: CredentialProvider = { [unowned self] in
        CredentialProvider(viewController: self, extensionContext: extensionContext, afterDecryption: NotificationCenterDispatcher.showOTPNotification)
    }()

    private lazy var passwordsTableEntries = PasswordStore.shared.fetchPasswordEntityCoreData(withDir: false)
        .map(PasswordTableEntry.init)

    override func viewDidLoad() {
        super.viewDidLoad()
        passwordsViewController.dataSource = PasswordsTableDataSource(entries: passwordsTableEntries)
        passwordsViewController.selectionDelegate = self
        passwordsViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        passcodelock.presentPasscodeLockIfNeeded(self) {
            self.view.isHidden = true
        } after: { [unowned self] in
            view.isHidden = false
            credentialProvider.identifier = serviceIdentifiers.first
            let url = serviceIdentifiers.first
                .map(\.identifier)
                .flatMap(URL.init)
            passwordsViewController.navigationItem.prompt = url?.host
            passwordsViewController.showPasswordsWithSuggestion(matching: url?.host ?? "")
        }
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        credentialProvider.identifier = credentialIdentity.serviceIdentifier
        guard exists(credentialIdentity) else {
            removeSuggestion(credentialIdentity)
            extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.credentialIdentityNotFound.rawValue))
            return
        }
        if !PasscodeLock.shared.hasPasscode, Defaults.isRememberPGPPassphraseOn, !Defaults.isYubiKeyEnabled {
            credentialProvider.credentialsWithoutUserInteraction(for: credentialIdentity)
        } else {
            extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userInteractionRequired.rawValue))
        }
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        guard exists(credentialIdentity) else {
            removeSuggestion(credentialIdentity)
            prepareCredentialList(for: [credentialIdentity.serviceIdentifier])
            return
        }
        passcodelock.presentPasscodeLockIfNeeded(self) {
            self.view.isHidden = true
        } after: { [unowned self] in
            credentialProvider.credentials(for: credentialIdentity)
        }
    }

    private func exists(_ credentialIdentity: ASPasswordCredentialIdentity) -> Bool {
        credentialIdentity.recordIdentifier.flatMap(PasswordStore.shared.fetchPasswordEntity(with:)) != nil
    }

    private func removeSuggestion(_ credentialIdentity: ASPasswordCredentialIdentity) {
        if let path = credentialIdentity.recordIdentifier {
            CredentialIdentities.remove(path: path)
        }
    }

    @objc
    private func cancel(_: AnyObject?) {
        extensionContext.cancelRequest(withError: NSError(domain: "PassExtension", code: 0))
    }
}

extension CredentialProviderViewController: PasswordSelectionDelegate {
    func selected(password: PasswordTableEntry) {
        credentialProvider.persistAndProvideCredentials(with: password.passwordEntity.path)
    }
}
