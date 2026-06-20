import SwiftUI

struct LoginSheet: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var manualCode = ""
    @State private var showManual = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if let url = viewModel.authorizeURL {
                    LoginWebView(
                        url: url,
                        onCode: { viewModel.completeLogin(rawCode: $0) },
                        onError: { errorText = $0 }
                    )
                } else {
                    ContentUnavailableView("Kein Login möglich", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("Bei Claude anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { viewModel.showingLogin = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Manuell") { showManual = true }
                }
            }
            .alert("Login-Fehler", isPresented: .constant(errorText != nil)) {
                Button("OK") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .sheet(isPresented: $showManual) {
                manualSheet
            }
        }
    }

    private var manualSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Falls der Login im Fenster nicht klappt (z. B. Google-Anmeldung): Öffne die Seite in Safari, melde dich an, und füge den angezeigten Code hier ein.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let url = viewModel.authorizeURL {
                        Link("Login-Seite in Safari öffnen", destination: url)
                    }
                }
                Section("Code einfügen") {
                    TextField("Authorization Code", text: $manualCode, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Einlösen") {
                        let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !code.isEmpty else { return }
                        showManual = false
                        viewModel.completeLogin(rawCode: code)
                    }
                    .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Manueller Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { showManual = false }
                }
            }
        }
    }
}
