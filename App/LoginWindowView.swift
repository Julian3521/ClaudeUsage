import SwiftUI
import AppKit

/// Login window: paste the existing Claude Code access token (it carries the
/// `user:profile` scope the usage endpoint requires).
struct LoginWindowView: View {
    let viewModel: UsageViewModel
    var onClose: () -> Void = {}

    @State private var token = ""

    /// Copies the existing Claude Code access token to the clipboard.
    private static let tokenCommand = #"security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import sys,json;print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" | pbcopy"#

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sign in").font(.title3.bold())
                Text("Uses your existing Claude Code login (it already has the required user:profile scope). Everything stays local — only the usage request goes to Anthropic.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Open Terminal.")
                        step(2, "Run this command — it copies your token to the clipboard:")
                        HStack(alignment: .top) {
                            Text(Self.tokenCommand)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(Self.tokenCommand, forType: .string)
                            }
                        }
                        step(3, "Paste it below (⌘V), then “Save & connect”.")
                    }
                    .padding(4)
                }

                Text("Token").font(.headline)
                TextField("sk-ant-oat01-…", text: $token, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .font(.system(.body, design: .monospaced))

                if let error = viewModel.loginError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { onClose() }
                    Button("Save & connect") { viewModel.loginWithToken(token) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 460)
        .onChange(of: viewModel.shouldDismissLogin) { _, done in
            if done { onClose() }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").bold().monospacedDigit()
            Text(text)
            Spacer(minLength: 0)
        }
    }
}
