//
//  Passport.swift
//  pass
//

import Foundation
import passKit

/// Everything needed to set up the app, as handed over by the `passport` command line tool.
struct Passport: Equatable {
    enum ParseError: Error, Equatable {
        case unsupportedVersion
        case missingField(String)
        case missingPGPKey
    }

    static let version = "1"

    let url: URL
    let username: String?
    let branch: String
    let name: String?
    let email: String?
    let sshKey: String?
    let pgpKey: String
    /// The public keys of the store's other recipients, so entries saved here stay readable for them.
    let recipientKeys: [String]

    init(parsing text: String) throws {
        let entry = try Entry(parsing: text)
        guard entry.value(of: "passport") == Self.version else {
            throw ParseError.unsupportedVersion
        }

        func value(of key: String) -> String? {
            entry.value(of: key).flatMap { $0.isEmpty ? nil : $0 }
        }

        guard let url = value(of: "url").flatMap(URL.init(string:)) else {
            throw ParseError.missingField("url")
        }
        guard let branch = value(of: "branch") else {
            throw ParseError.missingField("branch")
        }
        let blocks = entry.body.armoredBlocks
        guard let pgpKey = blocks.first(where: { $0.hasPrefix("-----BEGIN PGP PRIVATE KEY BLOCK-----") }) else {
            throw ParseError.missingPGPKey
        }

        self.url = url
        self.username = value(of: "user")
        self.branch = branch
        self.name = value(of: "name")
        self.email = value(of: "email")
        self.sshKey = blocks.first { !$0.hasPrefix("-----BEGIN PGP") }
        self.pgpKey = pgpKey
        self.recipientKeys = blocks.filter { $0.hasPrefix("-----BEGIN PGP PUBLIC KEY BLOCK-----") }
    }
}

/// Collects the frames of a looping `passport` QR code, which may arrive in any order.
struct PassportScanner {
    enum Result: Equatable {
        case unrecognized
        case scanned(Int, total: Int)
        case completed(String)
    }

    private var id: String?
    private var frames = [Int: String]()
    private var count = 0

    mutating func add(frame: String) -> Result {
        guard let match = frame.wholeMatch(of: #/passport ([0-9a-f]+) (\d+)/(\d+)\n(.*)/#.dotMatchesNewlines()),
              let index = Int(match.2), let count = Int(match.3), (1 ... count).contains(index) else {
            return .unrecognized
        }
        let id = String(match.1)
        if id != self.id || count != self.count {
            self.id = id
            self.count = count
            frames = [:]
        }
        frames[index] = String(match.4)
        guard frames.count == count else {
            return .scanned(frames.count, total: count)
        }
        return .completed((1 ... count).compactMap { frames[$0] }.joined())
    }

    mutating func reset() {
        self = Self()
    }
}
