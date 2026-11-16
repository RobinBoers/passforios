//
//  SettingsView.swift
//  pass
//

import passKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: SettingsModel

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
            }
            .navigationTitle("Settings")
            .toolbar {
                if model.isPresented {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: model.close)
                    }
                }
            }
        }
    }

    private var storeSection: some View {
        SwiftUI.Section {
            NavigationLink {
                StoreView()
            } label: {
                LabeledContent("Store", value: model.hasStore ? model.remoteName : "NotSet".localize())
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
            // From iOS 18 on, AutoFill fills in codes itself, so the notification with the code is optional.
            if #available(iOS 18.0, *) {
                Toggle("ShowCodeAfterFilling", isOn: model.codeNotification)
            }
            if showsCodeNotification {
                Toggle("AutoCopyOTP", isOn: model.autoCopyOTP)
            }
            Button("ClearSavedSuggestions") {
                model.clearSuggestions()
            }
            .disabled(!model.hasSavedSuggestions)
        } header: {
            Text("AutoFill")
        } footer: {
            Text(showsCodeNotification ? "AutoCopyOTPExplanation." : "ShowCodeAfterFilling.")
        }
    }

    private var showsCodeNotification: Bool {
        if #available(iOS 18.0, *) {
            return model.codeNotification.wrappedValue
        }
        return true
    }

    private var keysSummary: String {
        let keys = [model.pgpKeyIDs.isEmpty ? nil : "GPG", model.hasSSHKey ? "SSH" : nil].compactMap(\.self)
        return keys.isEmpty ? "NotSet".localize() : keys.joined(separator: ", ")
    }
}
