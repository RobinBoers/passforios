//
//  PasswordGenerator.swift
//  passKit
//
//  Created by Danny Moesch on 27.02.20.
//  Copyright © 2020 Bob Sun. All rights reserved.
//

/// Generates Apple-style passwords like `abcdef-ghij4k-lmnopq-rsTuvw`.
public struct PasswordGenerator: Codable {
    public static let lengthLimits = (min: 8, max: 64)

    private static let characters = "abcdefghijklmnopqrstuvwxyz0123456789"

    public var length = 27

    public init(length: Int = 27) {
        self.length = length
    }

    public var limitedLength: Int {
        max(Self.lengthLimits.min, min(Self.lengthLimits.max, length))
    }

    public func generate() -> String {
        let length = limitedLength
        var password = (0 ..< length).map { index -> Character in
            index % 7 == 6 && index < length - 1 ? "-" : Self.characters.randomElement()!
        }

        let positions = password.indices.filter { password[$0] != "-" }

        if !password.contains(where: \.isNumber) {
            password[positions.randomElement()!] = Character(String(Int.random(in: 0 ... 9)))
        }

        if let position = positions.filter({ password[$0].isLetter }).randomElement() {
            password[position] = Character(password[position].uppercased())
        }

        return String(password)
    }
}
