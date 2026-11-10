//
//  OnboardingView.swift
//  pass
//

import passKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        Group {
            switch model.step {
            case .welcome:
                WelcomeStep()
            case .passphrase:
                PassphraseStep()
            case .autoFill:
                AutoFillStep()
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
    }
}

/// The layout every step shares: a header, content, and buttons pinned to the bottom.
private struct StepLayout<Content: View, Buttons: View>: View {
    let symbol: String?
    let title: LocalizedStringKey
    let message: LocalizedStringKey
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
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(Capsule().fill(.tint))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct WelcomeStep: View {
    @EnvironmentObject private var model: OnboardingModel

    var body: some View {
        StepLayout(symbol: nil, title: "PassForIos", message: "WelcomeMessage.") {
            VStack(alignment: .leading, spacing: 24) {
                Feature(symbol: "arrow.triangle.2.circlepath", title: "FeatureSync", message: "FeatureSync.")
                Feature(symbol: "person.badge.key", title: "FeatureAutoFill", message: "FeatureAutoFill.")
                Feature(symbol: "faceid", title: "FeaturePrivate", message: "FeaturePrivate.")
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

private struct PassphraseStep: View {
    @EnvironmentObject private var model: OnboardingModel

    @State private var passphrase = ""
    @State private var remember = true
    @FocusState private var isFocused: Bool

    var body: some View {
        StepLayout(symbol: "key.horizontal", title: "PgpPassphrase", message: "PgpPassphraseMessage.") {
            VStack(alignment: .leading, spacing: 16) {
                SecureField("Passphrase", text: $passphrase)
                    .textContentType(.password)
                    .focused($isFocused)
                    .submitLabel(.continue)
                    .onSubmit(verify)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
                Toggle("RememberPgpKeyPassphrase", isOn: $remember)
                if let error = model.passphraseError {
                    Text(error).foregroundStyle(.red)
                }
            }
            .onAppear {
                isFocused = true
            }
        } buttons: {
            Button(action: verify) {
                if model.isVerifying {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(passphrase.isEmpty || model.isVerifying)
            Button("Skip", action: model.next)
                .frame(minHeight: 44)
        }
    }

    private func verify() {
        guard !passphrase.isEmpty else {
            return
        }
        model.verify(passphrase: passphrase, remember: remember)
    }
}

private struct AutoFillStep: View {
    @EnvironmentObject private var model: OnboardingModel

    @State private var showsCodes = false

    var body: some View {
        StepLayout(symbol: "person.badge.key", title: "AutoFill", message: "AutoFillMessage.") {
            VStack(alignment: .leading, spacing: 16) {
                if model.isAutoFillEnabled {
                    Label("AutoFillIsOn", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("TurnOnAutoFill", action: model.turnOnAutoFill)
                }
                Toggle("ShowOneTimeCodes", isOn: $showsCodes)
                    .onChange(of: showsCodes) { isOn in
                        if isOn {
                            model.allowOneTimeCodeNotifications()
                        }
                    }
                Text("ShowOneTimeCodes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if AppLock.isAvailable {
                    Toggle("LockWith(%@)".localize(AppLock.methodName), isOn: model.appLock)
                }
            }
        } buttons: {
            Button("Done", action: model.finish)
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}
