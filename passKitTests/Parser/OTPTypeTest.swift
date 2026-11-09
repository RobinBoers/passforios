//
//  OTPTypeTest.swift
//  passKitTests
//
//  Created by Danny Moesch on 01.12.18.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

import OneTimePassword
import XCTest

@testable import passKit

final class OTPTypeTest: XCTestCase {
    func testInitFromToken() {
        let secret = Data("secret".utf8)

        let totpGenerator = Generator(factor: .timer(period: 30.0), secret: secret, algorithm: .sha1, digits: 6)!
        let totpToken = Token(name: "", issuer: "", generator: totpGenerator)
        XCTAssertEqual(OTPType(token: totpToken), .totp)

        let hotpGenerator = Generator(factor: .counter(4), secret: secret, algorithm: .sha1, digits: 6)!
        let hotpToken = Token(name: "", issuer: "", generator: hotpGenerator)
        XCTAssertEqual(OTPType(token: hotpToken), .hotp)

        XCTAssertEqual(OTPType(token: nil), .none)
    }

    func testDescription() {
        XCTAssertEqual(OTPType.totp.description, "TimeBased".localize())
        XCTAssertEqual(OTPType.hotp.description, "HmacBased".localize())
        XCTAssertEqual(OTPType.none.description, "None".localize())
    }
}
