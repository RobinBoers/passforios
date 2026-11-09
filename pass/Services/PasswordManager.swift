//
//  PasswordManager.swift
//  pass
//
//  Created by Mingshen Sun on 17/1/2021.
//  Copyright © 2021 Bob Sun. All rights reserved.
//

import passKit
import UIKit

class PasswordManager {
    private let viewController: UIViewController

    init(viewController: UIViewController) {
        self.viewController = viewController
    }

    func providePasswordPasteboard(with passwordPath: String) {
        decryptPassword(in: viewController, with: passwordPath) { password in
            SecurePasteboard.shared.copy(textToCopy: password.password)
            Feedback.success()
        }
    }

    func addPassword(with password: Password) {
        encryptPassword(in: viewController, with: password) {
            Feedback.success()
        }
    }
}
