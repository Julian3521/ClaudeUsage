import SwiftUI
import AppKit

/// The login window. Two ways in:
///  • Token  — paste a token from `claude setup-token` (reliable, subscription).
///  • Browser — the OAuth web flow (may hit Google-SSO / host issues).
struct LoginWindowView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss

    /// Copies the existing Claude Code access token (which has the user:profile
    /// scope the usage endpoint requires) to the clipboard.
    static let tokenCommand = #"security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import sys,json;print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" | pbcopy"#

    enum Mode: String, CaseIterable { case token = "Token", browser = "Browser" }
    @State private var mode: Mode = .token
    @State private var token = ""
    @State private var manualCode = ""
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch mode {
            case .token: tokenView
            case .browser: browserView
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .onAppear { if viewModel.pkce == nil { viewModel.startLogin() } }
        .onChange(of: viewModel.shouldDismissLogin) { _, done in
            if done { dismiss() }
        }
    }

    // MARK: - Token (recommended)

    private var tokenView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Mit Token anmelden (empfohlen)").font(.title3.bold())
                Text("Verwendet dein bereits vorhandenes Claude-Code-Login (es hat die nötige user:profile-Berechtigung). Alles bleibt lokal — nur der Usage-Aufruf geht an Anthropic.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Terminal öffnen.")
                        step(2, "Diesen Befehl ausführen — er kopiert dein Token in die Zwischenablage:")
                        HStack(alignment: .top) {
                            Text(Self.tokenCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            Button("Kopieren") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(Self.tokenCommand, forType: .string)
                            }
                        }
                        step(3, "Unten einfügen (⌘V), dann „Speichern & verbinden\".")
                    }
                    .padding(4)
                }

                Text("Token").font(.headline)
                TextField("sk-ant-oat01-…", text: $token, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .font(.system(.body, design: .monospaced))

                if let err = viewModel.loginError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Abbrechen") { dismiss() }
                    Button("Speichern & verbinden") {
                        viewModel.loginWithToken(token)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").bold().monospacedDigit()
            Text(text)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Browser (OAuth)

    private var browserView: some View {
        VStack(spacing: 0) {
            if let url = viewModel.authorizeURL {
                LoginWebView(
                    url: url,
                    onCode: { viewModel.completeLogin(rawCode: $0) },
                    onError: { errorText = $0 }
                )
            } else {
                Text("Kein Login möglich")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack(spacing: 10) {
                if let url = viewModel.authorizeURL {
                    Link("Im Browser öffnen", destination: url)
                }
                TextField("Code aus dem Browser einfügen", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                Button("Einlösen") {
                    let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !code.isEmpty else { return }
                    viewModel.completeLogin(rawCode: code)
                }
                .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
        }
        .alert("Login-Fehler", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }
}
