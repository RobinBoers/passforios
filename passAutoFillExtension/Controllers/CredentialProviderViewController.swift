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
    private lazy var passwordsViewController: PasswordsViewController = (children.first as! UINavigationController).viewControllers.first as! PasswordsViewController

    private lazy var credentialProvider: CredentialProvider = { [unowned self] in
        CredentialProvider(viewController: self, extensionContext: extensionContext, afterDecryption: NotificationCenterDispatcher.showOTPNotification)
    }()

    private lazy var passwordsTableEntries = PasswordStore.shared.fetchPasswordEntityCoreData(withDir: false)
        .map(PasswordTableEntry.init)

    /// Whether the list was asked for a verification code rather than a password.
    private var isOneTimeCodeRequest = false

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
        unlock { [unowned self] in
            credentialProvider.identifier = serviceIdentifiers.first
            let url = serviceIdentifiers.first
                .map(\.identifier)
                .flatMap(URL.init)
            passwordsViewController.navigationItem.prompt = url?.host
            passwordsViewController.showPasswordsWithSuggestion(matching: url?.host ?? "")
        }
    }

    @available(iOS 18.0, *)
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        isOneTimeCodeRequest = true
        prepareCredentialList(for: serviceIdentifiers)
    }

    @available(iOS 17.0, *)
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        if #available(iOS 18.0, *), let identity = credentialRequest.credentialIdentity as? ASOneTimeCodeCredentialIdentity {
            guard exists(identity.recordIdentifier) else {
                identity.recordIdentifier.map(CredentialIdentities.remove(path:))
                extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.credentialIdentityNotFound.rawValue))
                return
            }
            if !AppLock.isEnabled, Defaults.isRememberPGPPassphraseOn {
                credentialProvider.oneTimeCodeWithoutUserInteraction(for: identity)
            } else {
                extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userInteractionRequired.rawValue))
            }
        } else if let identity = credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity {
            provideCredentialWithoutUserInteraction(for: identity)
        } else {
            extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.credentialIdentityNotFound.rawValue))
        }
    }

    @available(iOS 17.0, *)
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        if #available(iOS 18.0, *), let identity = credentialRequest.credentialIdentity as? ASOneTimeCodeCredentialIdentity {
            guard exists(identity.recordIdentifier) else {
                identity.recordIdentifier.map(CredentialIdentities.remove(path:))
                prepareOneTimeCodeCredentialList(for: [identity.serviceIdentifier])
                return
            }
            unlock { [unowned self] in
                credentialProvider.oneTimeCode(for: identity)
            }
        } else if let identity = credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity {
            prepareInterfaceToProvideCredential(for: identity)
        }
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        credentialProvider.identifier = credentialIdentity.serviceIdentifier
        guard exists(credentialIdentity) else {
            removeSuggestion(credentialIdentity)
            extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.credentialIdentityNotFound.rawValue))
            return
        }
        if !AppLock.isEnabled, Defaults.isRememberPGPPassphraseOn {
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
        unlock { [unowned self] in
            credentialProvider.credentials(for: credentialIdentity)
        }
    }

    private func unlock(then action: @escaping () -> Void) {
        guard AppLock.isEnabled else {
            action()
            return
        }
        view.isHidden = true
        AppLock.authenticate(reason: "UnlockPass".localize()) { [weak self] success in
            guard let self else {
                return
            }
            guard success else {
                extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
                return
            }
            view.isHidden = false
            action()
        }
    }

    private func exists(_ credentialIdentity: ASPasswordCredentialIdentity) -> Bool {
        exists(credentialIdentity.recordIdentifier)
    }

    private func exists(_ recordIdentifier: String?) -> Bool {
        recordIdentifier.flatMap(PasswordStore.shared.fetchPasswordEntity(with:)) != nil
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
        if #available(iOS 18.0, *), isOneTimeCodeRequest {
            credentialProvider.persistAndProvideOneTimeCode(with: password.passwordEntity.path)
        } else {
            credentialProvider.persistAndProvideCredentials(with: password.passwordEntity.path)
        }
    }
}
