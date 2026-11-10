//
//  PGPInterface.swift
//  passKit
//
//  Created by Danny Moesch on 08.09.19.
//  Copyright © 2019 Bob Sun. All rights reserved.
//

protocol PGPInterface {
    func decrypt(encryptedData: Data, keyID: String?, passphrase: String) throws -> Data?

    /// Encrypts to the keys whose fingerprints end in the given IDs, or to the first key when there are none.
    func encrypt(plainData: Data, keyIDs: [String]) throws -> Data

    func containsPublicKey(with keyID: String) -> Bool

    func containsPrivateKey(with keyID: String) -> Bool

    var keyID: [String] { get }

    var shortKeyID: [String] { get }
}
