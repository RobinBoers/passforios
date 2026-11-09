//
//  CredentialProvider.swift
//  passAutoFillExtension
//
//  Created by Sun, Mingshen on 1/2/21.
//  Copyright © 2021 Bob Sun. All rights reserved.
//

import AuthenticationServices
import passKit

class CredentialProvider {
    private let viewController: UIViewController
    private let extensionContext: ASCredentialProviderExtensionContext
    private let afterDecryption: (Password) -> Void

    var identifier: ASCredentialServiceIdentifier?

    init(viewController: UIViewController, extensionContext: ASCredentialProviderExtensionContext, afterDecryption: @escaping (Password) -> Void) {
        self.viewController = viewController
        self.extensionContext = extensionContext
        self.afterDecryption = afterDecryption
    }

    func credentials(for identity: ASPasswordCredentialIdentity) {
        guard let recordIdentifier = identity.recordIdentifier else {
            return
        }

        decryptPassword(in: viewController, with: recordIdentifier) { password in
            self.extensionContext.completeRequest(withSelectedCredential: .from(password))
            self.afterDecryption(password)
        }
    }

    /// Decrypts with the remembered passphrase only. Anything that needs the user, like a forgotten passphrase,
    /// is handed back to the system, which then asks for the interface.
    func credentialsWithoutUserInteraction(for identity: ASPasswordCredentialIdentity) {
        guard let recordIdentifier = identity.recordIdentifier else {
            cancel(with: .credentialIdentityNotFound)
            return
        }

        DispatchQueue.global(qos: .userInteractive).async {
            let password = try? PasswordStore.shared.decrypt(path: recordIdentifier) { _ in "" }
            DispatchQueue.main.async {
                guard let password else {
                    self.cancel(with: .userInteractionRequired)
                    return
                }
                self.extensionContext.completeRequest(withSelectedCredential: .from(password))
                self.afterDecryption(password)
            }
        }
    }

    func persistAndProvideCredentials(with passwordPath: String) {
        decryptPassword(in: viewController, with: passwordPath) { password in
            if let identifier = self.identifier {
                CredentialIdentities.save(service: identifier, user: password.getUsernameForCompletion(), path: passwordPath)
            }
            self.extensionContext.completeRequest(withSelectedCredential: .from(password))
            self.afterDecryption(password)
        }
    }

    private func cancel(with code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}

extension ASPasswordCredential {
    static func from(_ password: Password) -> ASPasswordCredential {
        ASPasswordCredential(user: password.getUsernameForCompletion(), password: password.password)
    }
}
