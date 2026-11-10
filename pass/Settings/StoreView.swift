//
//  StoreView.swift
//  pass
//

import ObjectiveGit
import passKit
import SwiftUI

struct StoreView: View {
    @EnvironmentObject private var model: SettingsModel

    @State private var url = Defaults.gitURL.absoluteString
    @State private var branch = Defaults.gitBranchName
    @State private var username = Defaults.gitUsername
    @State private var authentication = Defaults.gitAuthenticationMethod
    @State private var format = Defaults.storeFormat

    var body: some View {
        Form {
            if model.hasStore {
                infoSection
            }
            remoteSection
            formatSection
            signatureSection
        }
        .navigationTitle("Store")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var infoSection: some View {
        SwiftUI.Section {
            LabeledContent("Passwords", value: model.storeInfo.passwords.formatted())
            LabeledContent("Size", value: model.storeInfo.size.formatted(.byteCount(style: .file)))
            LabeledContent("Commits", value: model.storeInfo.commits.map(String.init) ?? "ValueNotAvailable".localize())
            LabeledContent("LocalCommits", value: String(model.storeInfo.localCommits))
            LabeledContent("LastSynced", value: model.storeInfo.lastSynced?.formatted(date: .abbreviated, time: .shortened) ?? "SyncAgain?".localize())
            NavigationLink("CommitLogs") {
                CommitLogView()
            }
        }
    }

    private var remoteSection: some View {
        SwiftUI.Section {
            TextField("GitURL", text: $url)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            LabeledContent("Branch") {
                TextField("Branch", text: $branch)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            LabeledContent("Username") {
                TextField("Username", text: $username)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Picker("Authentication", selection: $authentication) {
                Text("Password").tag(GitAuthenticationMethod.password)
                Text("SSHKey").tag(GitAuthenticationMethod.key)
            }
            Button(LocalizedStringKey(model.hasStore ? "CloneAgain" : "Clone"), action: clone)
                .disabled(!canClone)
        } header: {
            Text("Remote")
        } footer: {
            Text("GitURLFormats.")
        }
    }

    private var formatSection: some View {
        SwiftUI.Section {
            Picker("Format", selection: $format) {
                ForEach(StoreFormat.allCases, id: \.self) { format in
                    Text(verbatim: format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: format) { format in
                Defaults.storeFormat = format
            }
        } header: {
            Text("Format")
        } footer: {
            Text(LocalizedStringKey(format == .sec ? "FormatSec." : "FormatPass."))
        }
    }

    private var signatureSection: some View {
        SwiftUI.Section {
            TextField("Name", text: model.signatureName)
                .textContentType(.name)
            TextField("Email", text: model.signatureEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("GitSignature")
        }
    }

    private var remote: URL? {
        URL(string: url.trimmed).flatMap { $0.absoluteString.isEmpty || $0.absoluteString == "https://" ? nil : $0 }
    }

    private var canClone: Bool {
        remote != nil && !branch.trimmed.isEmpty && (authentication == .password || model.hasSSHKey)
    }

    private func clone() {
        guard let remote else {
            return
        }
        let user = remote.user ?? (username.trimmed.isEmpty ? "git" : username.trimmed)
        model.clone(url: remote, branch: branch.trimmed, username: user, authentication: authentication)
    }
}

struct CommitLogView: View {
    @State private var commits = [GTCommit]()
    @State private var error: String?

    var body: some View {
        List(commits, id: \.sha) { commit in
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.message?.trimmed ?? "")
                HStack {
                    Text(commit.author?.name ?? "")
                    Spacer()
                    Text(commit.commitDate.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if let error {
                Text(error).foregroundStyle(.secondary).padding()
            }
        }
        .navigationTitle("CommitLogs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                commits = try PasswordStore.shared.getRecentCommits(count: 20)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
