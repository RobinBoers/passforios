//
//  OnboardingView.swift
//  pass
//

import passKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        NavigationStack(path: $model.path) {
            StepView(step: model.root)
                .id(model.root)
                .transition(.opacity)
                .navigationDestination(for: OnboardingModel.Step.self) { step in
                    StepView(step: step)
                }
        }
    }
}

private struct StepView: View {
    let step: OnboardingModel.Step

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            // Going back from here would clone again.
            .navigationBarBackButtonHidden(step == .gpgPassphrase)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .importing:
            ImportingStep()
        case .gitPassphrase:
            GitPassphraseStep()
        case .gpgPassphrase:
            GPGPassphraseStep()
        case .autoFill:
            AutoFillStep()
        case .oneTimeCodes:
            OneTimeCodesStep()
        case .appLock:
            AppLockStep()
        }
    }
}

/// The layout every step shares: a header, content, and buttons pinned to the bottom.
private struct StepLayout<Content: View, Buttons: View>: View {
    let symbol: String?
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    } else {
                        Image("Logo")
                            .resizable()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    if let message {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    content
                        .padding(.top, 16)
                }
                .padding(.horizontal, 32)
                .padding(.top, 64)
            }
            VStack(spacing: 12) {
                buttons
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(isEnabled ? .white : .secondary)
            .background(Capsule().fill(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill))))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct ImportingStep: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        StepLayout(symbol: "qrcode", title: "ImportingKeys") {
            ProgressView()
        } buttons: {
            EmptyView()
        }
        .task {
            model.importScannedKeys()
        }
    }
}

private struct WelcomeStep: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        StepLayout(symbol: nil, title: "PassForIos") {
            VStack(alignment: .leading, spacing: 24) {
                Feature(symbol: "arrow.triangle.2.circlepath", title: "FeatureSync", message: "FeatureSync.")
                Feature(symbol: "person.badge.key", title: "AutoFill", message: "FeatureAutoFill.")
                Feature(symbol: AppLock.symbolName, title: LocalizedStringKey("LockedWith(%@)".localize(AppLock.methodName)), message: "FeatureLock.")
            }
        } buttons: {
            Button("SetUpFromComputer", action: model.setUpFromComputer)
                .buttonStyle(PrimaryButtonStyle())
            Button("SetUpManually", action: model.setUpManually)
                .frame(minHeight: 44)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).foregroundStyle(.secondary)
            }
        }
    }
}

/// A secret to type in, with an option to remember it, shared by the Git and GPG steps.
private struct SecretStep: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let placeholder: LocalizedStringKey
    let action: (_ secret: String, _ remember: Bool) -> Void

    @EnvironmentObject private var model: OnboardingModel

    @State private var secret = ""
    @State private var remember = true
    @FocusState private var isFocused: Bool

    var body: some View {
        StepLayout(symbol: symbol, title: title, message: message) {
            VStack(alignment: .leading, spacing: 16) {
                SecureField(placeholder, text: $secret)
                    .textContentType(.password)
                    .focused($isFocused)
                    .submitLabel(.continue)
                    .onSubmit(submit)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                Toggle("RememberPassphrase", isOn: $remember)
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .onAppear {
                isFocused = true
            }
        } buttons: {
            Button(action: submit) {
                if model.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(secret.isEmpty || model.isWorking)
        }
    }

    private func submit() {
        guard !secret.isEmpty else {
            return
        }
        action(secret, remember)
    }
}

private struct GitPassphraseStep: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        SecretStep(
            symbol: model.usesSSHKey ? "key.horizontal" : "person.badge.key",
            title: model.usesSSHKey ? "SshPassphrase" : "GitPassword",
            message: model.usesSSHKey ? "SshPassphraseMessage." : "GitPasswordMessage.",
            placeholder: model.usesSSHKey ? "Passphrase" : "Password",
            action: model.clone
        )
    }
}

private struct GPGPassphraseStep: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        SecretStep(symbol: "key.horizontal", title: "PgpPassphrase", message: "PgpPassphraseMessage.", placeholder: "Passphrase", action: model.verify)
    }
}

private struct AutoFillStep: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        StepLayout(symbol: "person.badge.key", title: "AutoFill", message: "AutoFillMessage.") {
            if model.isAutoFillEnabled {
                Label("AutoFillIsOn", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } buttons: {
            if model.isAutoFillEnabled {
                Button("Continue") { model.go(to: .oneTimeCodes) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("TurnOnAutoFill", action: model.turnOnAutoFill)
                    .buttonStyle(PrimaryButtonStyle())
                Button("NotNow") { model.go(to: .oneTimeCodes) }
                    .frame(minHeight: 44)
            }
        }
    }
}

private struct OneTimeCodesStep: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        StepLayout(symbol: "bell.badge", title: "ShowOneTimeCodes", message: "ShowOneTimeCodes.") {
            EmptyView()
        } buttons: {
            Button("AllowNotifications", action: model.allowOneTimeCodeNotifications)
                .buttonStyle(PrimaryButtonStyle())
            Button("NotNow", action: model.afterOneTimeCodes)
                .frame(minHeight: 44)
        }
    }
}

private struct AppLockStep: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        StepLayout(symbol: AppLock.symbolName, title: LocalizedStringKey("LockWith(%@)".localize(AppLock.methodName)), message: "AppLockMessage.") {
            EmptyView()
        } buttons: {
            Button(LocalizedStringKey("UseMethod(%@)".localize(AppLock.methodName)), action: model.turnOnAppLock)
                .buttonStyle(PrimaryButtonStyle())
            Button("NotNow", action: model.finish)
                .frame(minHeight: 44)
        }
    }
}
