import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = UsageViewModel()
    @State private var showRaw = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Claude Usage")
                .toolbar {
                    if viewModel.isLoggedIn {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Aktualisieren", systemImage: "arrow.clockwise") {
                                    Task { await viewModel.refresh() }
                                }
                                Button("Rohdaten anzeigen", systemImage: "curlybraces") {
                                    showRaw = true
                                }
                                Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                    viewModel.logout()
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
        }
        .onAppear { viewModel.onAppear() }
        .sheet(isPresented: $viewModel.showingLogin) {
            LoginSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showRaw) {
            RawJSONView(text: viewModel.rawJSON)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loggedOut:
            loggedOut
        case .loading:
            ProgressView("Lade Nutzung…")
        case let .loaded(snapshot):
            loaded(snapshot)
        case let .error(message):
            errorView(message)
        }
    }

    private var loggedOut: some View {
        VStack(spacing: 20) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Claude-Nutzung als Widget")
                .font(.title2.bold())
            Text("Melde dich mit deinem Claude-Account an, um dein Session- und Wochenlimit zu sehen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Bei Claude anmelden") { viewModel.startLogin() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    private func loaded(_ snapshot: UsageSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack(spacing: 24) {
                    ringColumn("Session", percent: snapshot.sessionPercent, resetsAt: snapshot.sessionResetsAt)
                    ringColumn("Woche", percent: snapshot.weeklyPercent, resetsAt: snapshot.weeklyResetsAt)
                }
                .padding(.top, 12)

                VStack(spacing: 18) {
                    UsageBar(title: "Current session (5h)",
                             percent: snapshot.sessionPercent, resetsAt: snapshot.sessionResetsAt)
                    UsageBar(title: "Weekly · all models (7d)",
                             percent: snapshot.weeklyPercent, resetsAt: snapshot.weeklyResetsAt)
                    if let opus = snapshot.opusPercent {
                        UsageBar(title: "Weekly · Opus (7d)",
                                 percent: opus, resetsAt: snapshot.opusResetsAt)
                    }
                }
                .padding(.horizontal)

                Text("Stand: \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .refreshable { await viewModel.refresh() }
    }

    private func ringColumn(_ title: String, percent: Double, resetsAt: Date?) -> some View {
        VStack(spacing: 8) {
            UsageRing(percent: percent, lineWidth: 10)
                .frame(width: 110, height: 110)
            Text(title).font(.subheadline.weight(.medium))
            Text(UsageFormat.resetLabel(resetsAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Fehler").font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen") { Task { await viewModel.refresh() } }
                .buttonStyle(.bordered)
        }
        .padding(40)
    }
}

struct RawJSONView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "—" : text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Rohdaten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
