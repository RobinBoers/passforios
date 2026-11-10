//
//  CryptographicKeys.swift
//  passKit
//
//  Created by Danny Moesch on 29.06.19.
//  Copyright © 2019 Bob Sun. All rights reserved.
//

import CryptoKit

public protocol CryptographicKey {
    func getKeychainKey() -> String
    func getFileSharingPath() -> String
}

public enum PGPKey: CryptographicKey {
    case PUBLIC
    case PRIVATE

    public func getKeychainKey() -> String {
        switch self {
        case .PUBLIC:
            return "pgpPublicKey"
        case .PRIVATE:
            return "pgpPrivateKey"
        }
    }

    public func getFileSharingPath() -> String {
        switch self {
        case .PUBLIC:
            return Globals.iTunesFileSharingPGPPublic
        case .PRIVATE:
            return Globals.iTunesFileSharingPGPPrivate
        }
    }
}

public enum SSHKey: CryptographicKey {
    case PRIVATE

    public func getKeychainKey() -> String {
        switch self {
        case .PRIVATE:
            return "sshPrivateKey"
        }
    }

    public func getFileSharingPath() -> String {
        switch self {
        case .PRIVATE:
            return Globals.iTunesFileSharingSSHPrivate
        }
    }
}

public extension SSHKey {
    /// Whether an ASCII-armored private key is protected by a passphrase. PEM keys say `ENCRYPTED`;
    /// OpenSSH keys name their cipher, `none` when unprotected.
    static func isEncrypted(_ armor: String) -> Bool {
        if armor.contains("ENCRYPTED") {
            return true
        }
        return OpenSSHKey(armor: armor).map { $0.cipher != "none" } ?? false
    }

    /// The key type and SHA256 fingerprint, as `ssh-keygen -l` shows them, for OpenSSH keys.
    static func fingerprint(_ armor: String) -> String? {
        guard let key = OpenSSHKey(armor: armor) else {
            return nil
        }
        var reader = OpenSSHKey.Reader(data: key.publicKey)
        let type = reader.string().flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        let name = type.replacingOccurrences(of: "ssh-", with: "").split(separator: "-").first.map { $0.uppercased() } ?? ""
        let hash = Data(SHA256.hash(data: key.publicKey)).base64EncodedString().trimmingCharacters(in: ["="])
        return "\(name) SHA256:\(hash)"
    }
}

/// The unencrypted parts of an `openssh-key-v1` private key.
private struct OpenSSHKey {
    struct Reader {
        var data: Data

        mutating func string() -> Data? {
            guard data.count >= 4 else {
                return nil
            }
            let length = data.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            data = data.dropFirst(4)
            guard data.count >= length else {
                return nil
            }
            defer { data = data.dropFirst(length) }
            return data.prefix(length)
        }
    }

    let cipher: String
    let publicKey: Data

    init?(armor: String) {
        let body = armor.splitByNewline().filter { !$0.hasPrefix("-----") }.joined()
        let magic = Data("openssh-key-v1\0".utf8)
        guard armor.contains("BEGIN OPENSSH PRIVATE KEY"), let data = Data(base64Encoded: body), data.starts(with: magic) else {
            return nil
        }
        var reader = Reader(data: data.dropFirst(magic.count))
        guard let cipher = reader.string(), reader.string() != nil, reader.string() != nil, reader.data.count >= 4 else {
            return nil
        }
        // Skips the number of keys, of which there is one.
        reader.data = reader.data.dropFirst(4)
        guard let publicKey = reader.string() else {
            return nil
        }
        self.cipher = String(bytes: cipher, encoding: .utf8) ?? ""
        self.publicKey = Data(publicKey)
    }
}
