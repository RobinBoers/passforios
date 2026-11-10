//
//  KeysView.swift
//  pass
//

import passKit
import SwiftUI

struct KeysView: View {
    @EnvironmentObject private var model: SettingsModel

    @State private var editing: KeyKind?
    @State private var removing: KeyKind?

    var body: some View {
        Form {
            SwiftUI.Section {
                Button(action: model.setUpFromComputer) {
                    Label("SetUpFromComputer", systemImage: "qrcode.viewfinder")
                }
            } footer: {
                Text("SetUpFromComputer.")
            }

            SwiftUI.Section {
                if model.pgpKeyIDs.isEmpty {
                    Text("NotSet").foregroundStyle(.secondary)
                } else {
                    ForEach(model.pgpKeyIDs, id: \.self) { id in
                        Text(id).monospaced()
                    }
                }
                if model.pgpKeyIDs.isEmpty {
                    Button("PasteKey") { editing = .pgp }
                } else {
                    Button("RemoveKey", role: .destructive) { removing = .pgp }
                }
            } header: {
                Text("PGPKey")
            }

            SwiftUI.Section {
                if model.hasSSHKey {
                    Text(model.sshKeySummary ?? "Set".localize())
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button("RemoveKey", role: .destructive) { removing = .ssh }
                } else {
                    Text("NotSet").foregroundStyle(.secondary)
                    Button("PasteKey") { editing = .ssh }
                }
            } header: {
                Text("SSHKey")
            }
        }
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { kind in
            KeyPasteView(kind: kind)
        }
        .confirmationDialog(removing?.removeTitle ?? "", isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } }, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                switch removing {
                case .pgp:
                    model.removePGPKey()
                case .ssh:
                    model.removeSSHKey()
                case nil:
                    break
                }
            }
        }
    }
}

enum KeyKind: String, Identifiable {
    case pgp, ssh

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        self == .pgp ? "PGPKey" : "SSHKey"
    }

    var removeTitle: String {
        (self == .pgp ? "RemoveGpgKey?" : "RemoveSshKey?").localize()
    }
}

/// Pasting an ASCII-armored private key, the fallback for when `passport` is not at hand.
private struct KeyPasteView: View {
    let kind: KeyKind

    @EnvironmentObject private var model: SettingsModel
    @Environment(\.dismiss) private var dismiss

    @State private var armor = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    TextEditor(text: $armor)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 240)
                } footer: {
                    Text(LocalizedStringKey(kind == .pgp ? "PastePgpKeyExplanation." : "PasteSshKeyExplanation."))
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: save)
                        .disabled(armor.trimmed.isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            switch kind {
            case .pgp:
                try model.importPGPKey(armor)
            case .ssh:
                try model.importSSHKey(armor)
            }
            Feedback.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
