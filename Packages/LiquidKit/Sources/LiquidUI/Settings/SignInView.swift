import AuthenticationServices
import SwiftUI
import XKit

struct SignInView: View {
    @Bindable var model: AppModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isShowingClientID = false
    @State private var isShowingWebNotice = false
    @State private var isShowingWebLogin = false

    var body: some View {
        ZStack {
            LiquidBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                AppMark()
                    .frame(width: 112, height: 112)
                VStack(spacing: 10) {
                    Text("LiquidX")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                    Text("Your X timeline, made of glass.\nNative on iPhone, iPad and Mac.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                VStack(spacing: 12) {
                    if let error = model.signInError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular.tint(.red.opacity(0.25)), in: .rect(cornerRadius: 16))
                    }

                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            Button {
                                if model.effectiveClientID.isEmpty {
                                    isShowingClientID = true
                                } else {
                                    Task { await model.signIn(using: webAuthenticationSession) }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if model.isSigningIn {
                                        ProgressView().controlSize(.small).tint(.white)
                                    }
                                    Text("Sign in with X").font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accent)
                            .controlSize(.extraLarge)
                            .disabled(model.isSigningIn)

                            Button {
                                Task { await model.startDemo() }
                            } label: {
                                Text("Explore the Demo").font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.extraLarge)
                            .tint(.white)
                        }
                    }

                    Button {
                        isShowingWebNotice = true
                    } label: {
                        HStack(spacing: 8) {
                            Text("Use your x.com login instead")
                            Text("Unofficial")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.25), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)

                    Button {
                        isShowingClientID = true
                    } label: {
                        Text(model.effectiveClientID.isEmpty ? "Set up your X developer app" : "Using your X developer app · Change")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .frame(maxWidth: 420)

                Text("LiquidX is an independent open-source client and is not affiliated with X Corp.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .environment(\.colorScheme, .dark)
        }
        .sheet(isPresented: $isShowingClientID) {
            ClientIDSheet(model: model)
        }
        .sheet(isPresented: $isShowingWebNotice) {
            WebSessionNotice {
                // Present the login once the notice sheet has gone away.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    isShowingWebLogin = true
                }
            }
        }
        .sheet(isPresented: $isShowingWebLogin) {
            WebLoginView { credentials in
                Task { await model.signIn(with: credentials) }
            }
        }
        #if DEBUG
        .task {
            // Debug-only: start the real OAuth flow on launch, for testing the
            // sign-in sheet without UI automation.
            if UserDefaults.standard.bool(forKey: "LiquidXAutoSignIn"), !model.effectiveClientID.isEmpty {
                await model.signIn(using: webAuthenticationSession)
            }
            if UserDefaults.standard.bool(forKey: "LiquidXWebLogin") {
                isShowingWebLogin = true
            }
        }
        #endif
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("")
        #endif
    }
}

struct ClientIDSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("OAuth 2.0 Client ID", text: $draft)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .font(.body.monospaced())
                } footer: {
                    if !model.bundledClientID.isEmpty {
                        Text("Leave empty to use the Client ID this build was configured with.")
                    }
                }
                Section("How to get one") {
                    Step(number: 1, text: "Open developer.x.com and create a Project and an App.")
                    Step(number: 2, text: "In User authentication settings, choose OAuth 2.0 with type \"Native App\" and Read and write permissions.")
                    Step(number: 3, text: "Add \(OAuthConfiguration.redirectURI.absoluteString) as a Callback URI.")
                    Step(number: 4, text: "Copy the OAuth 2.0 Client ID here. No secret is needed.")
                    Link(destination: URL(string: "https://developer.x.com/en/portal/dashboard")!) {
                        Label("Open the X Developer Portal", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("X Developer App")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.clientID = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .onAppear { draft = model.clientID }
        #if os(macOS)
        .frame(width: 480, height: 460)
        #endif
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Theme.accent.opacity(0.2), in: Circle())
            Text(text)
        }
    }
}

/// Slowly drifting dark mesh gradient behind the sign-in screen.
struct LiquidBackdrop: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5 + 0.1 * sin(t * 0.3), 0], [1, 0],
                    [0, 0.5 + 0.1 * cos(t * 0.25)], [0.5 + 0.15 * cos(t * 0.2), 0.5 + 0.15 * sin(t * 0.35)], [1, 0.5 + 0.1 * sin(t * 0.3)],
                    [0, 1], [0.5 + 0.1 * cos(t * 0.3), 1], [1, 1],
                ],
                colors: [
                    .black, Color(red: 0.02, green: 0.08, blue: 0.2), .black,
                    Color(red: 0.03, green: 0.2, blue: 0.4), Color(red: 0.11, green: 0.5, blue: 0.85), Color(red: 0.05, green: 0.1, blue: 0.3),
                    .black, Color(red: 0.05, green: 0.12, blue: 0.28), .black,
                ]
            )
        }
    }
}

/// The app mark: an "X" etched into a glass droplet.
struct AppMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.tint(Theme.accent.opacity(0.25)), in: .circle)
            Image(systemName: "xmark")
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: Theme.accent.opacity(0.8), radius: 16)
        }
        .accessibilityHidden(true)
    }
}
