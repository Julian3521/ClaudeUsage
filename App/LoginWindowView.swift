import SwiftUI

/// The login window: hosts the OAuth web view, with a manual code fallback.
struct LoginWindowView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showManual = false
    @State private var manualCode = ""
    @State private var errorText: String?

    var body: some View {
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
            HStack {
                Button("Manuell…") { showManual = true }
                Spacer()
                Button("Abbrechen") { dismiss() }
            }
            .padding(8)
        }
        .frame(minWidth: 480, minHeight: 600)
        .onAppear { if viewModel.pkce == nil { viewModel.startLogin() } }
        .onChange(of: viewModel.shouldDismissLogin) { _, done in
            if done { dismiss() }
        }
        .alert("Login-Fehler", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .sheet(isPresented: $showManual) { manualSheet }
    }

    private var manualSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manueller Login").font(.headline)
            Text("Falls der Login im Fenster nicht klappt (z. B. Google-Anmeldung): Öffne die Seite im Browser, melde dich an und füge den angezeigten Code hier ein.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = viewModel.authorizeURL {
                Link("Login-Seite im Browser öffnen", destination: url)
            }
            TextField("Authorization Code", text: $manualCode, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Spacer()
                Button("Schließen") { showManual = false }
                Button("Einlösen") {
                    let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !code.isEmpty else { return }
                    showManual = false
                    viewModel.completeLogin(rawCode: code)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
