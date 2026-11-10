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

    var asIdentity: ASPasswordCredentialIdentity {
        ASPasswordCredentialIdentity(
            serviceIdentifier: ASCredentialServiceIdentifier(identifier: service, type: ASCredentialServiceIdentifier.IdentifierType(rawValue: serviceType) ?? .URL),
            user: user,
            recordIdentifier: path
        )
    }
}

/// The QuickType suggestions offered by AutoFill. The system store cannot be read back, so the suggestions are
/// mirrored in the shared defaults, which lets them follow the password store when entries are moved or removed.
public enum CredentialIdentities {
    /// Whether there are suggestions to clear; unknown before they were first mirrored, so assumed then.
    public static var isEmpty: Bool {
        Defaults.hasKey(\.credentialIdentities) && Defaults.credentialIdentities.isEmpty
    }

    public static func save(service: ASCredentialServiceIdentifier, user: String, path: String) {
        var identities = Defaults.credentialIdentities.filter { $0.service != service.identifier || $0.path != path }
        identities.append(SavedCredentialIdentity(service: service.identifier, serviceType: service.type.rawValue, user: user, path: path))
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
            ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities.map(\.asIdentity))
        }
    }
}
