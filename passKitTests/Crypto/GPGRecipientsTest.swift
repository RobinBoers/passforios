//
//  GPGRecipientsTest.swift
//  passKitTests
//

import ObjectivePGP
import XCTest

@testable import passKit

final class GPGRecipientsTest: XCTestCase {
    private let keys = RSA2048_RSA4096.publicKeys

    private func fingerprint(of recipient: String) throws -> String {
        try GPGRecipients.fingerprints(for: [recipient], in: keys)[0]
    }

    func testKeyIDs() throws {
        for id in RSA2048_RSA4096.fingerprints {
            XCTAssertTrue(try fingerprint(of: id).hasSuffix(id.uppercased()))
            XCTAssertTrue(try fingerprint(of: "0x\(id)!").hasSuffix(id.uppercased()))
        }
    }

    func testUserIDs() throws {
        let key = try XCTUnwrap(ObjectivePGP.readKeys(from: Data(keys.utf8)).first?.publicKey)
        let userID = try XCTUnwrap(key.users.first?.userID)
        let expected = key.fingerprint.description.uppercased()

        XCTAssertEqual(try fingerprint(of: userID), expected)
        XCTAssertEqual(try fingerprint(of: userID.uppercased()), expected)
        XCTAssertEqual(try fingerprint(of: "=\(userID)"), expected)
        XCTAssertThrowsError(try fingerprint(of: "=\(userID.dropLast())"))
    }

    func testUnknownRecipient() {
        XCTAssertThrowsError(try GPGRecipients.fingerprints(for: [RSA2048_RSA4096.fingerprints[0], "nobody"], in: keys)) {
            XCTAssertEqual($0 as? AppError, AppError.pgpPublicKeyNotFound(keyID: "nobody"))
        }
    }

    func testRead() throws {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: store) }

        XCTAssertEqual(GPGRecipients.read(from: store), [])
        try "Alice <alice@example.com>\n\n  D862027E \n".write(to: store.appendingPathComponent(".gpg-id"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GPGRecipients.read(from: store), ["Alice <alice@example.com>", "D862027E"])
    }
}
