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
    @State private var isShowingURLFormats = false
    @State private var isConfirmingClone = false

    var body: some View {
        Form {
            infoSection
            remoteSection
            signatureSection
        }
        .navigationTitle("Store")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var infoSection: some View {
        SwiftUI.Section {
            Picker("Format", selection: $format) {
                ForEach(StoreFormat.allCases, id: \.self) { format in
                    Text(verbatim: format.rawValue).tag(format)
                }
            }
            .onChange(of: format) { format in
                Defaults.storeFormat = format
            }
            if model.hasStore {
                LabeledContent("Passwords", value: model.storeInfo.passwords.formatted())
                LabeledContent("Size", value: model.storeInfo.size.formatted(.byteCount(style: .file)))
                NavigationLink {
                    CommitLogView()
                } label: {
                    LabeledContent("Commits", value: model.storeInfo.commits?.formatted() ?? "ValueNotAvailable".localize())
                }
            }
        }
    }

    private var remoteSection: some View {
        SwiftUI.Section {
            urlRow
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
            remoteAction
        } header: {
            Text("Remote")
        } footer: {
            if model.hasStore {
                Text("LastSynced(%@)".localize(model.storeInfo.lastSynced?.formatted(date: .abbreviated, time: .shortened) ?? "SyncAgain?".localize()))
            }
        }
        .alert("GitURLFormats", isPresented: $isShowingURLFormats) {
            Button("Ok", role: .cancel) {}
        } message: {
            Text("GitURLFormats.")
        }
        .confirmationDialog("Overwrite?", isPresented: $isConfirmingClone, titleVisibility: .visible) {
            Button("Overwrite", role: .destructive, action: clone)
        } message: {
            Text("OperationWillOverwriteData.")
        }
    }

    private var urlRow: some View {
        HStack {
            TextField("GitURL", text: $url)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                isShowingURLFormats = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("GitURLFormats")
        }
    }

    /// Syncs the store as it is, or clones again once the remote is changed.
    @ViewBuilder private var remoteAction: some View {
        if model.hasStore, !isRemoteChanged {
            Button(action: model.sync) {
                HStack {
                    Text("Sync")
                    Spacer()
                    if model.storeInfo.localCommits > 0 {
                        Text(model.storeInfo.localCommits, format: .number)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(.red, in: Capsule())
                    }
                }
            }
        } else {
            Button("Clone") {
                if model.hasStore {
                    isConfirmingClone = true
                } else {
                    clone()
                }
            }
            .disabled(!canClone)
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

    private var isRemoteChanged: Bool {
        url.trimmed != Defaults.gitURL.absoluteString || branch.trimmed != Defaults.gitBranchName
            || username.trimmed != Defaults.gitUsername || authentication != Defaults.gitAuthenticationMethod
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
        username = user
        model.clone(url: remote, branch: branch.trimmed, username: user, authentication: authentication)
    }
}

struct CommitLogView: View {
    @State private var commits = [GTCommit]()
    @State private var error: String?
    @State private var isLoading = true

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
            if isLoading {
                ProgressView()
            } else if let error {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView {
                        Label("CouldNotLoadHistory", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else {
                    Text(error).foregroundStyle(.secondary).padding()
                }
            }
        }
        .navigationTitle("CommitLogs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PasswordStore.shared.getRecentCommits(count: 20) }
            }.value
            switch result {
            case let .success(commits):
                self.commits = commits
            case let .failure(error):
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
