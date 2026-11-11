//
//  Proto.swift
//  pass
//

/// The protos `sec` users are likely to have, with a name and a symbol for each; others show their own name.
struct KnownProto {
    let name: String
    let titleKey: String
    let symbol: String

    /// In the order the add menu lists them.
    static let all = [
        Self(name: "card", titleKey: "ProtoCard", symbol: "creditcard"),
        Self(name: "license", titleKey: "ProtoLicense", symbol: "checkmark.seal"),
        Self(name: "database", titleKey: "ProtoDatabase", symbol: "cylinder"),
        Self(name: "ssh", titleKey: "ProtoSsh", symbol: "terminal"),
        Self(name: "imap", titleKey: "ProtoImap", symbol: "envelope"),
        Self(name: "smtp", titleKey: "ProtoSmtp", symbol: "paperplane"),
        Self(name: "wifi", titleKey: "ProtoWifi", symbol: "wifi"),
        Self(name: "web", titleKey: "ProtoWeb", symbol: "globe"),
    ]

    /// Kept last in the add menu, nearest the thumb, with other protos before them.
    static let bottom: Set = ["wifi", "web"]

    static func named(_ name: String) -> Self? {
        all.first { $0.name == name }
    }
}
