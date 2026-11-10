//
//  SettingsView.swift
//  pass
//

import passKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    @State private var isConfirmingDiscard = false
    @State private var isConfirmingErase = false

    var body: some View {
        NavigationStack {
            Form {
                storeSection
                securitySection
                autoFillSection
                SwiftUI.Section {
                    Toggle("ShowFolders", isOn: model.showFolders)
                }
                SwiftUI.Section {
                    NavigationLink("About") {
                        AboutView()
                    }
                }
                dangerSection
            }
            .navigationTitle("Settings")
        }
    }

    private var storeSection: some View {
        SwiftUI.Section {
            NavigationLink {
                StoreView()
            } label: {
                LabeledContent("Store", value: model.hasStore ? Defaults.gitURL.host ?? "" : "NotSet".localize())
            }
            NavigationLink {
                KeysView()
            } label: {
                LabeledContent("Keys", value: keysSummary)
            }
            Button {
                model.setUpFromComputer()
            } label: {
                Label("SetUpFromComputer", systemImage: "qrcode.viewfinder")
            }
        }
    }

    private var securitySection: some View {
        SwiftUI.Section {
            if AppLock.isAvailable {
                Toggle("LockWith(%@)".localize(AppLock.methodName), isOn: model.appLock)
            }
            Toggle("RememberPgpKeyPassphrase", isOn: model.rememberPGPPassphrase)
            Toggle("RememberGitCredentialPassphrase", isOn: model.rememberGitCredential)
        } header: {
            Text("Security")
        }
    }

    private var autoFillSection: some View {
        SwiftUI.Section {
            Toggle("AutoCopyOTP", isOn: model.autoCopyOTP)
            Button("ClearSavedSuggestions") {
                model.clearSuggestions()
            }
        } header: {
            Text("AutoFill")
        } footer: {
            Text("AutoCopyOTPExplanation.")
        }
    }

    private var dangerSection: some View {
        SwiftUI.Section {
            Button("DiscardAllLocalChanges", role: .destructive) {
                isConfirmingDiscard = true
            }
            .disabled(!model.hasStore)
            Button("ErasePasswordStoreData", role: .destructive) {
                isConfirmingErase = true
            }
        }
        .confirmationDialog("DiscardAllLocalChanges?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("DiscardAllLocalChanges", role: .destructive) {
                model.discardLocalChanges()
            }
        } message: {
            Text("DiscardExplanation.")
        }
        .confirmationDialog("ErasePasswordStoreData?", isPresented: $isConfirmingErase, titleVisibility: .visible) {
            Button("ErasePasswordStoreData", role: .destructive) {
                model.erase()
            }
        } message: {
            Text("EraseExplanation.")
        }
    }

    private var keysSummary: String {
        switch model.pgpKeyIDs.count {
        case 0:
            "NotSet".localize()
        case 1:
            model.pgpKeyIDs[0]
        default:
            "Multiple".localize()
        }
    }
}
