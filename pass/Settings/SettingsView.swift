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
                SwiftUI.Section {
                    Toggle("ShowFolders", isOn: model.showFolders)
                }
                securitySection
                autoFillSection
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
                LabeledContent("Store", value: model.hasStore ? model.remoteHost : "NotSet".localize())
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
            Toggle("RememberGpgPassphrase", isOn: model.rememberPGPPassphrase)
            Toggle(model.rememberGitCredentialTitle, isOn: model.rememberGitCredential)
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
            Button("DiscardChanges", role: .destructive) {
                isConfirmingDiscard = true
            }
            .disabled(model.storeInfo.localCommits == 0)
            Button("EraseStore", role: .destructive) {
                isConfirmingErase = true
            }
        }
        .confirmationDialog("DiscardChanges?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("DiscardChanges", role: .destructive) {
                model.discardLocalChanges()
            }
        } message: {
            Text("DiscardExplanation.")
        }
        .confirmationDialog("EraseStore?", isPresented: $isConfirmingErase, titleVisibility: .visible) {
            Button("EraseStore", role: .destructive) {
                model.erase()
            }
        } message: {
            Text("EraseExplanation.")
        }
    }

    private var keysSummary: String {
        let keys = [model.pgpKeyIDs.isEmpty ? nil : "GPG", model.hasSSHKey ? "SSH" : nil].compactMap(\.self)
        return keys.isEmpty ? "NotSet".localize() : keys.joined(separator: ", ")
    }
}
