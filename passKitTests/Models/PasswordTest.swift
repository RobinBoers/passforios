//
//  PasswordTest.swift
//  passKitTests
//
//  Created by Danny Moesch on 02.05.18.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

import XCTest

@testable import passKit

final class PasswordTest: XCTestCase {
    func testURL() {
        let password = getPasswordObjectWith(content: "")

        XCTAssertEqual(password.path, PASSWORD_PATH)
        XCTAssertEqual(password.namePath, PASSWORD_PATH)
    }

    func testEmptyFile() {
        ["", "\n"].forEach { fileContent in
            let password = getPasswordObjectWith(content: fileContent)

            XCTAssertEqual(password.password, "")
            XCTAssertEqual(password.plainData, fileContent.data(using: .utf8))
            XCTAssert(password.additionalFields.isEmpty)
            XCTAssertNil(password.user)
            XCTAssertNil(password.urlString)
            XCTAssertNil(password.notes)
            XCTAssertEqual(password.otpType, .none)
        }
    }

    func testWebEntry() {
        let password = getPasswordObjectWith(content: "proto: web\nuser: me\npass!: \(PASSWORD_STRING)\nurl: https://secure.com\n\nsome notes\n")

        XCTAssertEqual(password.password, PASSWORD_STRING)
        XCTAssertEqual(password.user, "me")
        XCTAssertEqual(password.urlString, "https://secure.com")
        XCTAssertEqual(password.notes, "some notes")
        XCTAssertEqual(password.additionalFields, [
            Field(key: "proto", value: "web"),
            Field(key: "url", value: "https://secure.com"),
        ])
        XCTAssertEqual(password.getUsernameForCompletion(), "me")
    }

    func testSSHEntryUsesBodyAsPrimary() {
        let password = getPasswordObjectWith(content: "proto: ssh\npub: ssh-ed25519 AAAA\npass!: passphrase\n\nprivate key\n")

        XCTAssertEqual(password.password, "private key")
        XCTAssertNil(password.notes)
        XCTAssertEqual(password.additionalFields, [
            Field(key: "proto", value: "ssh"),
            Field(key: "pub", value: "ssh-ed25519 AAAA"),
            Field(key: "pass", value: "passphrase", isSecret: true),
        ])
    }

    func testMalformedEntryBecomesBody() {
        let password = getPasswordObjectWith(content: "\(PASSWORD_STRING)\nlogin: me")

        XCTAssertEqual(password.password, "")
        XCTAssertEqual(password.notes, "\(PASSWORD_STRING)\nlogin: me")
        XCTAssert(password.additionalFields.isEmpty)
    }

    func testUsernameFallsBackToName() {
        let password = getPasswordObjectWith(content: "pass!: x", path: "web/example.com.gpg")

        XCTAssertEqual(password.getUsernameForCompletion(), "example.com")
    }

    func testTOTP() {
        let password = getPasswordObjectWith(content: "pass!: x\notp!: \(TOTP_URL)")

        XCTAssertEqual(password.otpType, .totp)
        XCTAssertNotNil(password.currentOtp)
        XCTAssert(password.additionalFields.isEmpty)
    }

    func testSteamTOTP() {
        let password = getPasswordObjectWith(content: "otp!: \(STEAM_TOTP_URL)")

        XCTAssertEqual(password.otpType, .totp)
        XCTAssertEqual(password.currentOtp?.count, 5)
    }

    func testInvalidOtpauth() {
        let password = getPasswordObjectWith(content: "otp!: otpauth://totp/no-secret")

        XCTAssertEqual(password.otpType, .none)
        XCTAssertNil(password.currentOtp)
    }

    func testNextHOTPUpdatesFieldInPlace() {
        let password = getPasswordObjectWith(content: "user: me\notp!: \(HOTP_URL)\npass!: x\n\nnotes\n")

        XCTAssertEqual(password.otpType, .hotp)
        XCTAssertNotNil(password.getNextHotp())
        XCTAssertNotEqual(password.changed, 0)
        XCTAssertEqual(password.entry.fields.map(\.key), ["user", "otp", "pass"])
        XCTAssert(password.entry.fields[1].value.contains("counter=1"))
        XCTAssertEqual(password.notes, "notes")
    }

    func testUpdatePassword() {
        let password = getPasswordObjectWith(content: "pass!: old")

        password.updatePassword(name: "password", path: PASSWORD_PATH, plainText: "pass!: new\n")

        XCTAssertEqual(password.password, "new")
        XCTAssertEqual(password.changed, PasswordChange.content.rawValue)
    }

    func testInitFromEntry() {
        let entry = Entry(fields: [Field(key: "pass", value: "x", isSecret: true)])
        let password = Password(name: "password", path: PASSWORD_PATH, entry: entry)

        XCTAssertEqual(password.plainText, "pass!: x\n")
        XCTAssertEqual(password.entry, entry)
    }
}
