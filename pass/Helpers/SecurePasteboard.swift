//
//  SecurePasteboard.swift
//  pass
//
//  Created by Yishi Lin on 2017/7/27.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

class SecurePasteboard {
    static let shared = SecurePasteboard()

    /// Copies to this device only, not to others through Universal Clipboard, and lets the system clear the
    /// copy after `expirationTime` seconds, unless something else was copied since.
    func copy(textToCopy: String?, expirationTime: Double = 45) {
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if expirationTime > 0 {
            options[.expirationDate] = Date(timeIntervalSinceNow: expirationTime)
        }
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: textToCopy ?? ""]], options: options)
    }
}
