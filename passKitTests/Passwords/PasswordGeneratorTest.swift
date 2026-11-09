//
//  PasswordGeneratorTest.swift
//  passKitTests
//
//  Created by Danny Moesch on 26.02.20.
//  Copyright © 2020 Bob Sun. All rights reserved.
//

import XCTest

@testable import passKit

final class PasswordGeneratorTest: XCTestCase {
    func testLimitedLength() {
        XCTAssertEqual(PasswordGenerator(length: 27).limitedLength, 27)
        XCTAssertEqual(PasswordGenerator(length: -3).limitedLength, PasswordGenerator.lengthLimits.min)
        XCTAssertEqual(PasswordGenerator(length: 128).limitedLength, PasswordGenerator.lengthLimits.max)
    }

    func testAppleStyleShape() {
        (0 ..< 100).forEach { _ in
            let password = PasswordGenerator().generate()

            XCTAssertNotNil(password.wholeMatch(of: #/[a-z0-9]{6}(-[a-z0-9]{6}){3}/#.ignoresCase()), password)
        }
    }

    func testDashesNeverTrail() {
        (PasswordGenerator.lengthLimits.min ... PasswordGenerator.lengthLimits.max).forEach { length in
            let password = PasswordGenerator(length: length).generate()

            XCTAssertEqual(password.count, length)
            XCTAssertFalse(password.hasPrefix("-"), password)
            XCTAssertFalse(password.hasSuffix("-"), password)
            XCTAssertFalse(password.contains("--"), password)
        }
    }

    func testContainsDigitAndUppercaseLetter() {
        (0 ..< 100).forEach { _ in
            let password = PasswordGenerator().generate()

            XCTAssert(password.contains(where: \.isNumber), password)
            XCTAssertEqual(password.filter(\.isUppercase).count, 1, password)
        }
    }
}
