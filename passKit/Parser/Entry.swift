//
//  Entry.swift
//  passKit
//
//  Created by Danny Moesch on 16.08.18.
//  Copyright © 2018 Bob Sun. All rights reserved.
//

/// A store entry in the format of `sec`: a header of `key: value` lines, where `key!:` marks a secret,
/// optionally followed by a blank line and a free-form body.
/// How a store lays out its entries.
public enum StoreFormat: String, CaseIterable {
    /// The password on the first line, then `key: value` lines and notes in any order.
    case pass
    /// A header of `key: value` lines with the password in `pass!:`, then a blank line and the notes.
    case sec
}

public struct Entry: Equatable {
    public enum ParseError: Error, Equatable {
        case malformedLine(Int)
        case reservedKey(Int)
    }

    public var fields: [Field]
    public var body: String
    public var format: StoreFormat

    public init(fields: [Field] = [], body: String = "", format: StoreFormat = Defaults.storeFormat) {
        self.fields = fields
        self.body = body
        self.format = format
    }

    public init(parsing plainText: String, format: StoreFormat = Defaults.storeFormat) throws {
        switch format {
        case .pass:
            self.init(parsingPass: plainText)
        case .sec:
            try self.init(parsingSec: plainText)
        }
    }

    private init(parsingSec plainText: String) throws {
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
        self.init(fields: fields, body: body, format: .sec)
    }

    /// Lines that are not `key: value` are notes. Bare `otpauth://` URIs become the `otp` field, and a
    /// `key:` must be followed by a space, so URLs in notes stay notes.
    private init(parsingPass plainText: String) {
        var lines = plainText.splitByNewline()
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        var fields = [Field(key: Constants.PASSWORD_KEYWORD, value: lines.first ?? "", isSecret: true)]
        var notes = [String]()
        for line in lines.dropFirst() {
            if line.hasPrefix(Constants.OTPAUTH_URL_START) {
                fields.append(Field(key: Constants.OTP_KEYWORD, value: line, isSecret: true))
            } else if let field = Field(line: line), !field.isSecret, field.key != Constants.PASSWORD_KEYWORD,
                      field.key != Constants.BODY_KEYWORD, line.hasPrefix(field.key + ": ") || line == field.key + ":" {
                fields.append(field)
            } else {
                notes.append(line)
            }
        }
        self.init(fields: fields, body: notes.joined(separator: "\n"), format: .pass)
    }

    /// Fields left empty are dropped, like `sec edit` does.
    public var plainText: String {
        switch format {
        case .sec:
            let header = fields.filter { !$0.value.isEmpty }.map(\.line)
            let lines = body.isEmpty ? header : header + ["", body]
            return lines.joined(separator: "\n") + "\n"
        case .pass:
            let password = value(of: Constants.PASSWORD_KEYWORD) ?? ""
            let others = fields.filter { $0.key != Constants.PASSWORD_KEYWORD && !$0.value.isEmpty }.map { field in
                field.key == Constants.OTP_KEYWORD && field.isOtpauth ? field.value : "\(field.key): \(field.value)"
            }
            let lines = [password] + others + (body.isEmpty ? [] : [body])
            return lines.joined(separator: "\n") + "\n"
        }
    }

    public func value(of key: String) -> String? {
        fields.first { $0.key == key }?.value
    }

    public var isBodyPrimary: Bool {
        format == .sec && value(of: Constants.PROTO_KEYWORD) == Constants.SSH_PROTO
    }

    public var primary: String? {
        if isBodyPrimary {
            return body.isEmpty ? nil : body
        }
        return value(of: Constants.PASSWORD_KEYWORD)
    }
}
