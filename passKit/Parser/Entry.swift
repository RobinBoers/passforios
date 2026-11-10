//
//  Entry.swift
//  passKit
//
//  Created by Danny Moesch on 16.08.18.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

/// A store entry: a header of `key: value` lines, where `key!:` marks a secret,
/// optionally followed by a blank line and a free-form body.
public struct Entry: Equatable {
    public enum ParseError: Error, Equatable {
        case malformedLine(Int)
        case reservedKey(Int)
    }

    public var fields: [Field]
    public var body: String

    public init(fields: [Field] = [], body: String = "") {
        self.fields = fields
        self.body = body
    }

    public init(parsing plainText: String) throws {
        var lines = plainText.splitByNewline()[...]
        var fields: [Field] = []
        var number = 0

        while let line = lines.popFirst(), !line.isEmpty {
            number += 1
            guard let field = Field(line: line) else {
                throw ParseError.malformedLine(number)
            }
            guard field.key != Constants.BODY_KEYWORD else {
                throw ParseError.reservedKey(number)
            }
            fields.append(field)
        }

        var body = lines.joined(separator: "\n")
        while body.hasSuffix("\n") {
            body.removeLast()
        }
        self.init(fields: fields, body: body)
    }

    /// Fields left empty are dropped.
    public var plainText: String {
        let header = fields.filter { !$0.value.isEmpty }.map(\.line)
        let lines = body.isEmpty ? header : header + ["", body]
        return lines.joined(separator: "\n") + "\n"
    }

    public func value(of key: String) -> String? {
        fields.first { $0.key == key }?.value
    }

    public var isBodyPrimary: Bool {
        value(of: Constants.PROTO_KEYWORD) == Constants.SSH_PROTO
    }

    public var primary: String? {
        if isBodyPrimary {
            return body.isEmpty ? nil : body
        }
        return value(of: Constants.PASSWORD_KEYWORD)
    }
}
