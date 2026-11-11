//
//  CredentialIdentities.swift
//  passKit
//

import AuthenticationServices
import SwiftyUserDefaults

public struct SavedCredentialIdentity: Codable, Equatable, DefaultsSerializable {
    var service: String
    var serviceType: Int
    var user: String
    var path: String
    /// Suggests the entry's verification code rather than its password.
    var isOneTimeCode = false

    private var serviceIdentifier: ASCredentialServiceIdentifier {
        ASCredentialServiceIdentifier(identifier: service, type: ASCredentialServiceIdentifier.IdentifierType(rawValue: serviceType) ?? .URL)
    }

    var asIdentity: ASPasswordCredentialIdentity {
        ASPasswordCredentialIdentity(serviceIdentifier: serviceIdentifier, user: user, recordIdentifier: path)
    }

    @available(iOS 18.0, *) var asEntry: any ASCredentialIdentity {
        guard isOneTimeCode else {
            return asIdentity
        }
        return ASOneTimeCodeCredentialIdentity(serviceIdentifier: serviceIdentifier, label: user, recordIdentifier: path)
    }
}

public extension SavedCredentialIdentity {
    /// Suggestions saved before verification codes lack the flag.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.service = try container.decode(String.self, forKey: .service)
        self.serviceType = try container.decode(Int.self, forKey: .serviceType)
        self.user = try container.decode(String.self, forKey: .user)
        self.path = try container.decode(String.self, forKey: .path)
        self.isOneTimeCode = try container.decodeIfPresent(Bool.self, forKey: .isOneTimeCode) ?? false
    }
}

/// The QuickType suggestions offered by AutoFill. The system store cannot be read back, so the suggestions are
/// mirrored in the shared defaults, which lets them follow the password store when entries are moved or removed.
public enum CredentialIdentities {
    /// Whether there are suggestions to clear; unknown before they were first mirrored, so assumed then.
    public static var isEmpty: Bool {
        Defaults.hasKey(\.credentialIdentities) && Defaults.credentialIdentities.isEmpty
    }

    /// Remembers the entry as a suggestion for the service, for its password or for its verification code.
    public static func save(service: ASCredentialServiceIdentifier, user: String, path: String, isOneTimeCode: Bool = false) {
        var identities = Defaults.credentialIdentities.filter { identity in
            identity.service != service.identifier || identity.path != path || identity.isOneTimeCode != isOneTimeCode
        }
        identities.append(SavedCredentialIdentity(service: service.identifier, serviceType: service.type.rawValue, user: user, path: path, isOneTimeCode: isOneTimeCode))
        publish(identities)
    }

    public static func remove(path: String) {
        publish(Defaults.credentialIdentities.filter { $0.path != path })
    }

    public static func move(from oldPath: String, to newPath: String) {
        publish(Defaults.credentialIdentities.map { identity in
            var identity = identity
            if identity.path == oldPath {
                identity.path = newPath
            }
            return identity
        })
    }

    /// Drops the suggestions of entries that no longer exist.
    public static func prune(keeping exists: (String) -> Bool) {
        // Suggestions saved before they were mirrored are unknown, so the first prune replaces them all.
        let isMirrored = Defaults.hasKey(\.credentialIdentities)
        let identities = Defaults.credentialIdentities.filter { exists($0.path) }
        if !isMirrored || identities != Defaults.credentialIdentities {
            publish(identities)
        }
    }

    public static func removeAll(completion: @escaping (Error?) -> Void) {
        Defaults.credentialIdentities = []
        ASCredentialIdentityStore.shared.removeAllCredentialIdentities { _, error in
            completion(error)
        }
    }

    private static func publish(_ identities: [SavedCredentialIdentity]) {
        Defaults.credentialIdentities = identities
        ASCredentialIdentityStore.shared.getState { state in
            guard state.isEnabled else {
                return
            }
            if #available(iOS 18.0, *) {
                ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities.map(\.asEntry))
            } else {
                ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities.filter { !$0.isOneTimeCode }.map(\.asIdentity))
            }
        }
    }
}
