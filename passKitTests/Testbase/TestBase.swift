//
//  TestBase.swift
//  passKitTests
//
//  Created by Danny Moesch on 08.12.18.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

import XCTest

@testable import passKit

let PASSWORD_PATH = "/path/to/password"
let PASSWORD_STRING = "abcd1234"
let TOTP_URL = "otpauth://totp/email@email.com?secret=abcd1234"
let STEAM_TOTP_URL = "otpauth://totp/username?secret=12345678901234567890&issuer=Steam&algorithm=SHA1&digits=5&period=30&representation=steamguard"
let HOTP_URL = "otpauth://hotp/email@email.com?secret=abcd1234"

func getPasswordObjectWith(content: String, path: String? = nil) -> Password {
    Password(name: "password", path: path ?? PASSWORD_PATH, plainText: content)
}
