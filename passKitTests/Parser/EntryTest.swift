//
//  EntryTest.swift
//  passKitTests
//
//  Created by Danny Moesch on 18.08.18.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

import XCTest
@testable import passKit

final class EntryTest: XCTestCase {
    func testEmpty() throws {
        XCTAssertEqual(try Entry(parsing: ""), Entry())
        XCTAssertEqual(try Entry(parsing: "\n"), Entry())
    }

    func testHeader() throws {
        let entry = try Entry(parsing: "proto: web\nuser: me\npass!: secret\nurl:https://example.com\n")
        XCTAssertEqual(entry.fields, [
            Field(key: "proto", value: "web"),
            Field(key: "user", value: "me"),
            Field(key: "pass", value: "secret", isSecret: true),
            Field(key: "url", value: "https://example.com"),
        ])
        XCTAssertEqual(entry.body, "")
    }

    func testValueKeepsWhitespaceAfterFirstSpace() throws {
        let entry = try Entry(parsing: "key:   spaced  ")
        XCTAssertEqual(entry.value(of: "key"), "  spaced  ")
    }

    func testValueMayContainColons() throws {
        let entry = try Entry(parsing: "otp!: otpauth://totp/a:b?secret=X")
        XCTAssertEqual(entry.fields, [Field(key: "otp", value: "otpauth://totp/a:b?secret=X", isSecret: true)])
    }

    func testBody() throws {
        let entry = try Entry(parsing: "pass!: x\n\nfirst\n\nsecond\n\n\n")
        XCTAssertEqual(entry.fields, [Field(key: "pass", value: "x", isSecret: true)])
        XCTAssertEqual(entry.body, "first\n\nsecond")
    }

    func testBodyOnly() throws {
        let entry = try Entry(parsing: "\nnot: a field\n")
        XCTAssertEqual(entry.fields, [])
        XCTAssertEqual(entry.body, "not: a field")
    }

    func testMalformedLine() {
        XCTAssertThrowsError(try Entry(parsing: "pass!: x\njust a password")) { error in
            XCTAssertEqual(error as? Entry.ParseError, .malformedLine(2))
        }
        XCTAssertThrowsError(try Entry(parsing: "some key: value")) { error in
            XCTAssertEqual(error as? Entry.ParseError, .malformedLine(1))
        }
    }

    func testReservedKey() {
        XCTAssertThrowsError(try Entry(parsing: "body: x")) { error in
            XCTAssertEqual(error as? Entry.ParseError, .reservedKey(1))
        }
    }

    func testPlainText() {
        let entry = Entry(
            fields: [
                Field(key: "user", value: "me"),
                Field(key: "pass", value: "secret", isSecret: true),
                Field(key: "url", value: ""),
            ],
            body: "notes"
        )
        XCTAssertEqual(entry.plainText, "user: me\npass!: secret\n\nnotes\n")
        XCTAssertEqual(Entry(body: "notes").plainText, "\nnotes\n")
        XCTAssertEqual(Entry().plainText, "\n")
    }

    func testRoundTrip() throws {
        for plainText in [
            "proto: web\nuser: me\npass!: secret\n",
            "proto: ssh\npub: ssh-ed25519 AAAA\n\n-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n",
            "\nonly a body\n",
        ] {
            XCTAssertEqual(try Entry(parsing: plainText).plainText, plainText)
        }
    }

    func testPrimary() throws {
        XCTAssertEqual(try Entry(parsing: "pass!: secret").primary, "secret")
        XCTAssertNil(try Entry(parsing: "user: me").primary)
        XCTAssertEqual(try Entry(parsing: "proto: ssh\npass!: ignored\n\nkey").primary, "key")
        XCTAssertNil(try Entry(parsing: "proto: ssh\npub: x").primary)
    }

    func testFieldKeyValidity() {
        XCTAssertTrue(Field.isValid(key: "smtp_host"))
        XCTAssertTrue(Field.isValid(key: "a.b-c"))
        XCTAssertFalse(Field.isValid(key: ""))
        XCTAssertFalse(Field.isValid(key: "some key"))
        XCTAssertFalse(Field.isValid(key: "key!"))
        XCTAssertFalse(Field.isValid(key: "body"))
    }

    func testPassFormat() {
        let plainText = "secret\nuser: me\nurl: https://example.com\notpauth://totp/a?secret=b\nsome notes\nhttps://example.org\n"
        let entry = try? Entry(parsing: plainText, format: .pass)
        XCTAssertEqual(entry?.primary, "secret")
        XCTAssertEqual(entry?.value(of: "user"), "me")
        XCTAssertEqual(entry?.value(of: "url"), "https://example.com")
        XCTAssertEqual(entry?.value(of: "otp"), "otpauth://totp/a?secret=b")
        XCTAssertEqual(entry?.body, "some notes\nhttps://example.org")
        XCTAssertEqual(entry?.plainText, plainText)
    }

    func testPassFormatMovesNotesAfterFields() {
        let entry = try? Entry(parsing: "secret\na note\nuser: me\n", format: .pass)
        XCTAssertEqual(entry?.plainText, "secret\nuser: me\na note\n")
    }

    func testPassFormatKeepsSecretMarkersAndKeysInNotes() {
        let entry = try? Entry(parsing: "secret\nkey!: value\npass: other\nbody: text\n", format: .pass)
        XCTAssertEqual(entry?.fields.count, 1)
        XCTAssertEqual(entry?.body, "key!: value\npass: other\nbody: text")
    }

    func testPassFormatPasswordOnly() {
        XCTAssertEqual(try? Entry(parsing: "secret\n", format: .pass).plainText, "secret\n")
        XCTAssertEqual(try? Entry(parsing: "", format: .pass).primary, "")
    }

    func testPassFormatIgnoresProto() {
        let entry = try? Entry(parsing: "secret\nproto: ssh\nkey material\n", format: .pass)
        XCTAssertEqual(entry?.primary, "secret")
    }
}
