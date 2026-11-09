//
//  OTPType.swift
//  passKit
//
//  Created by Danny Moesch on 01.12.2018.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

import OneTimePassword

public enum OTPType: String {
    case totp = "TimeBased"
    case hotp = "HmacBased"
    case none = "None"

    var description: String {
        rawValue.localize()
    }

    init(token: Token?) {
        switch token?.generator.factor {
        case .some(.counter):
            self = .hotp
        case .some(.timer):
            self = .totp
        default:
            self = .none
        }
    }
}
