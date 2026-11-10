//
//  GPGRecipients.swift
//  passKit
//

import ObjectivePGP

/// Resolves the recipients a `.gpg-id` names to public keys, the way `gpg --recipient` does.
public enum GPGRecipients {
    /// The recipients in the `.gpg-id` at the root of the store; `sec` reads no other.
    public static func read(from storeURL: URL) -> [String] {
        guard let text = try? String(contentsOf: storeURL.appendingPathComponent(".gpg-id"), encoding: .utf8) else {
            return []
        }
        return text.splitByNewline().map(\.trimmed).filter { !$0.isEmpty }
    }

    /// The fingerprint of the key each recipient names, in order.
    public static func fingerprints(for recipients: [String], in armoredKeys: String) throws -> [String] {
        let keys = (try ObjectivePGP.readKeys(from: Data(armoredKeys.utf8))).compactMap(\.publicKey)
        return try recipients.map { recipient in
            guard let key = keys.first(where: { matches($0, recipient) }) else {
                throw AppError.pgpPublicKeyNotFound(keyID: recipient)
            }
            return key.fingerprint.description.uppercased()
        }
    }

    /// A hexadecimal key ID or fingerprint matches the key or any of its subkeys, `=` asks for an exact
    /// user ID, and anything else matches part of a user ID, ignoring case.
    static func matches(_ key: PartialKey, _ recipient: String) -> Bool {
        var spec = recipient
        if spec.hasSuffix("!") {
            spec.removeLast()
        }
        if spec.lowercased().hasPrefix("0x") {
            spec.removeFirst(2)
        }
        if spec.wholeMatch(of: #/[0-9A-Fa-f]{8}|[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40}/#) != nil {
            let fingerprints = [key.fingerprint] + key.subKeys.map(\.fingerprint)
            return fingerprints.contains { $0.description.uppercased().hasSuffix(spec.uppercased()) }
        }
        if spec.hasPrefix("=") {
            return key.users.contains { $0.userID == spec.dropFirst() }
        }
        return key.users.contains { $0.userID.localizedCaseInsensitiveContains(spec) }
    }
}
