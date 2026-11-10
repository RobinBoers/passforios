//
//  Password.swift
//  passKit
//
//  Created by Mingshen Sun on 2/2/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import Base32
import OneTimePassword

public class Password {
    public var name: String
    public var path: String
    public var plainText: String

    public var changed: Int = 0
    public var otpType: OTPType = .none

    public private(set) var entry = Entry()

    private var otpToken: Token? {
        didSet {
            otpType = OTPType(token: otpToken)
        }
    }

    public var namePath: String {
        (path as NSString).deletingPathExtension
    }

    public var nameFromPath: String? {
        URL(string: path)?.deletingPathExtension().pathComponents.last
    }

    public var password: String {
        entry.primary ?? ""
    }

    public var plainData: Data {
        plainText.data(using: .utf8)!
    }

    public var user: String? {
        entry.value(of: Constants.USER_KEYWORD)
    }

    public var urlString: String? {
        entry.value(of: Constants.URL_KEYWORD)
    }

    public var currentOtp: String? {
        otpToken?.currentPassword
    }

    /// How long a time-based one-time password lasts.
    public var otpPeriod: TimeInterval? {
        if case let .timer(period) = otpToken?.generator.factor {
            return period
        }
        return nil
    }

    /// Fields not already shown as the primary secret, user or one-time password.
    public var additionalFields: [Field] {
        entry.fields.filter { field in
            field.key != Constants.USER_KEYWORD
                && field.key != entry.primaryKey
                && !field.isOtpauth
        }
    }

    /// The body, unless it is the primary secret.
    public var notes: String? {
        entry.isBodyPrimary || entry.body.isEmpty ? nil : entry.body
    }

    public init(name: String, path: String, plainText: String) {
        self.name = name
        self.path = path
        self.plainText = plainText
        initEverything()
    }

    public convenience init(name: String, path: String, entry: Entry) {
        self.init(name: name, path: path, plainText: entry.plainText)
    }

    public func fileURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(path)
    }

    public func updatePassword(name: String, path: String, plainText: String) {
        guard self.plainText != plainText || self.path != path else {
            return
        }

        if self.plainText != plainText {
            self.plainText = plainText
            changed |= PasswordChange.content.rawValue
        }
        if self.path != path {
            self.path = path
            changed |= PasswordChange.path.rawValue
        }

        self.name = name
        initEverything()
    }

    private func initEverything() {
        // A malformed entry is shown as a body, so its content stays readable and editable.
        entry = (try? Entry(parsing: plainText)) ?? Entry(body: plainText)
        otpToken = entry.fields.first(where: \.isOtpauth)
            .flatMap { URL(string: $0.value) }
            .flatMap { Token(url: $0) }
    }

    /// Get the OTP description and the current password.
    public func getOtpStrings() -> (description: String, otp: String)? {
        guard otpToken != nil else {
            return nil
        }
        var description = otpType.description
        if case let .timer(period) = otpToken!.generator.factor {
            let timeSinceEpoch = Date().timeIntervalSince1970
            let validTime = Int(period - timeSinceEpoch.truncatingRemainder(dividingBy: period))
            description += " " + "ExpiresIn".localize(validTime)
        }
        return (description, otpToken!.currentPassword ?? "Error".localize())
    }

    // return the password strings
    // it is guaranteed that it is a HOTP password when we call this
    public func getNextHotp() -> String? {
        // increase the counter
        otpToken = otpToken?.updatedToken()

        guard let otpToken, var otpauth = try? otpToken.toURL().absoluteString,
              let index = entry.fields.firstIndex(where: \.isOtpauth) else {
            return nil
        }
        otpauth.append("&secret=")
        otpauth.append(MF_Base32Codec.base32String(from: otpToken.generator.secret))

        var entry = entry
        entry.fields[index].value = otpauth
        updatePassword(name: name, path: path, plainText: entry.plainText)

        // get and return the password
        return self.otpToken?.currentPassword
    }

    public func getUsernameForCompletion() -> String {
        user ?? nameFromPath ?? ""
    }
}
