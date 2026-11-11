//
//  Field.swift
//  passKit
//
//  Created by Danny Moesch on 30.09.18.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

import SwiftyUserDefaults

public struct Field: Hashable {
    public var key: String
    public var value: String
    public var isSecret: Bool

    public init(key: String, value: String, isSecret: Bool = false) {
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }

    init?(line: String) {
        guard let match = line.wholeMatch(of: #/([A-Za-z0-9_.\-]+)(!?): ?(.*)/#) else {
            return nil
        }
        self.init(key: String(match.1), value: String(match.3), isSecret: !match.2.isEmpty)
    }

    public static func isValid(key: String) -> Bool {
        key.wholeMatch(of: #/[A-Za-z0-9_.\-]+/#) != nil && key != Constants.BODY_KEYWORD
    }

    var line: String {
        "\(key)\(isSecret ? "!" : ""): \(value)"
    }

    /// A field for a verification code's `otpauth` URI, under the key the store's format uses for it.
    public static func oneTimeCode(_ otpauth: String, format: StoreFormat = Defaults.storeFormat) -> Self {
        let key = format == .pass ? Constants.OTP_KEYWORD : otpauth.hasPrefix("\(Constants.OTPAUTH)://hotp") ? "hotp" : "totp"
        return Self(key: key, value: otpauth, isSecret: true)
    }

    public var isOtpauth: Bool {
        value.hasPrefix(Constants.OTPAUTH_URL_START)
    }
}
