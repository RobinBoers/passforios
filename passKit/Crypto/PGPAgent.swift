//
//  PGPAgent.swift
//  passKit
//
//  Created by Yishi Lin on 2019/7/17.
//  Copyright © 2019 Bob Sun. All rights reserved.
//

import Gopenpgp

public class PGPAgent {
    public static let shared = PGPAgent()

    private let keyStore: KeyStore
    private var pgpInterface: PGPInterface?
    private var loadedKeys: (public: String, private: String)?
    private var latestDecryptStatus = true

    public init(keyStore: KeyStore = AppKeychain.shared) {
        self.keyStore = keyStore
    }

    public func initKeys() throws {
        uninitKeys()
        guard let publicKey: String = keyStore.get(for: PGPKey.PUBLIC.getKeychainKey()),
              let privateKey: String = keyStore.get(for: PGPKey.PRIVATE.getKeychainKey()) else {
            throw AppError.keyImport
        }
        do {
            pgpInterface = try GopenPGPInterface(publicArmoredKey: publicKey, privateArmoredKey: privateKey)
        } catch {
            pgpInterface = try ObjectivePGPInterface(publicArmoredKey: publicKey, privateArmoredKey: privateKey)
        }
        loadedKeys = (publicKey, privateKey)
    }

    /// Stores a private key, and as public keys its own plus those of the store's other recipients.
    public func importKeys(privateKey: String, otherPublicKeys: [String] = []) throws {
        var error: NSError?
        guard let key = CryptoNewKeyFromArmored(privateKey, &error) else {
            throw error ?? AppError.keyImport
        }
        let ownPublicKey = key.getArmoredPublicKey(&error)
        if let error {
            throw error
        }
        // Passphrases remembered for the same key stay, so setting up again does not ask for them.
        let isSameKey = (try? checkAndInit()) != nil && pgpInterface?.containsPrivateKey(with: key.getFingerprint()) == true
        if !isSameKey {
            AppKeychain.shared.removeAllContent(withPrefix: Globals.pgpKeyPassphrase)
        }
        try KeyFileManager.PublicPGP.importKey(from: ([ownPublicKey] + otherPublicKeys).joined(separator: "\n"))
        try KeyFileManager.PrivatePGP.importKey(from: privateKey)
        try initKeys()
        Defaults.pgpKeySource = .armor
    }

    public func uninitKeys() {
        pgpInterface = nil
        loadedKeys = nil
    }

    public var isInitialized: Bool {
        pgpInterface != nil
    }

    public func getKeyID() throws -> [String] {
        try checkAndInit()
        return pgpInterface?.keyID ?? []
    }

    public func getShortKeyID() throws -> [String] {
        try checkAndInit()
        return pgpInterface?.shortKeyID.sorted() ?? []
    }

    public func decrypt(encryptedData: Data, keyID: String, requestPGPKeyPassphrase: @escaping (String) throws -> String) throws -> Data? {
        // Init keys.
        try checkAndInit()
        guard let pgpInterface else {
            throw AppError.decryption
        }

        var keyID = keyID
        if !pgpInterface.containsPrivateKey(with: keyID) {
            if pgpInterface.keyID.count == 1 {
                keyID = pgpInterface.keyID.first!
            } else {
                throw AppError.pgpPrivateKeyNotFound(keyID: keyID)
            }
        }

        // Remember the previous status and set the current status
        let previousDecryptStatus = latestDecryptStatus
        latestDecryptStatus = false

        // Get the PGP key passphrase.
        var passphrase = ""
        if previousDecryptStatus == false {
            passphrase = try requestPGPKeyPassphrase(keyID)
        } else {
            passphrase = try keyStore.get(for: AppKeychain.getPGPKeyPassphraseKey(keyID: keyID)) ?? requestPGPKeyPassphrase(keyID)
        }
        // Decrypt.
        guard let result = try pgpInterface.decrypt(encryptedData: encryptedData, keyID: keyID, passphrase: passphrase) else {
            return nil
        }
        // The decryption step has succeed.
        latestDecryptStatus = true
        return result
    }

    public func encrypt(plainData: Data, keyID: String) throws -> Data {
        try checkAndInit()
        guard let pgpInterface else {
            throw AppError.encryption
        }
        var keyID = keyID
        if !pgpInterface.containsPublicKey(with: keyID) {
            if pgpInterface.keyID.count == 1 {
                keyID = pgpInterface.keyID.first!
            } else {
                throw AppError.pgpPublicKeyNotFound(keyID: keyID)
            }
        }
        return try pgpInterface.encrypt(plainData: plainData, keyIDs: [keyID])
    }

    /// Encrypts to everyone a `.gpg-id` names, so entries stay readable for every recipient.
    public func encrypt(plainData: Data, recipients: [String]) throws -> Data {
        try checkAndInit()
        guard let pgpInterface, let publicKeys: String = keyStore.get(for: PGPKey.PUBLIC.getKeychainKey()) else {
            throw AppError.encryption
        }
        let fingerprints = try GPGRecipients.fingerprints(for: recipients, in: publicKeys)
        return try pgpInterface.encrypt(plainData: plainData, keyIDs: fingerprints)
    }

    public func decrypt(encryptedData: Data, requestPGPKeyPassphrase: (String) throws -> String) throws -> Data? {
        // Remember the previous status and set the current status
        let previousDecryptStatus = latestDecryptStatus
        latestDecryptStatus = false
        // Init keys.
        try checkAndInit()
        // Get the PGP key passphrase.
        var passphrase = ""
        if previousDecryptStatus == false {
            passphrase = try requestPGPKeyPassphrase("")
        } else {
            passphrase = try keyStore.get(for: AppKeychain.getPGPKeyPassphraseKey(keyID: "")) ?? requestPGPKeyPassphrase("")
        }
        // Decrypt.
        guard let result = try pgpInterface!.decrypt(encryptedData: encryptedData, keyID: nil, passphrase: passphrase) else {
            return nil
        }
        // The decryption step has succeed.
        latestDecryptStatus = true
        return result
    }

    public func encrypt(plainData: Data) throws -> Data {
        try checkAndInit()
        guard let pgpInterface else {
            throw AppError.encryption
        }
        return try pgpInterface.encrypt(plainData: plainData, keyIDs: [])
    }

    public var isPrepared: Bool {
        keyStore.contains(key: PGPKey.PUBLIC.getKeychainKey())
            && keyStore.contains(key: PGPKey.PRIVATE.getKeychainKey())
    }

    /// The keychain is shared with the extensions, so another process may have replaced the keys since they were loaded.
    private func checkAndInit() throws {
        let publicKey: String? = keyStore.get(for: PGPKey.PUBLIC.getKeychainKey())
        let privateKey: String? = keyStore.get(for: PGPKey.PRIVATE.getKeychainKey())
        if pgpInterface == nil || publicKey != loadedKeys?.public || privateKey != loadedKeys?.private {
            try initKeys()
        }
    }
}
