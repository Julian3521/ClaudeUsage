import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettings()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            MenuBarSettings()
                .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }
            DisplaySettings()
                .tabItem { Label("Display", systemImage: "rectangle.grid.1x2") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 470, height: 410)
    }
}

private struct AccountSettings: View {
    private let viewModel = UsageViewModel.shared
    @State private var token = ""

    private static let tokenCommand = #"security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import sys,json;print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" | pbcopy"#

    var body: some View {
        Form {
            if viewModel.isSignedIn {
                Section("Account") {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Copy raw response") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.rawJSON, forType: .string)
                    }
                    Button("Sign out", role: .destructive) { viewModel.logout() }
                }
            } else {
                Section {
                    Text("Sign in with your Claude (Pro/Max) account. A browser window opens for the login; everything else stays local — only the usage request goes to Anthropic.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button {
                            viewModel.loginWithOAuth()
                        } label: {
                            if viewModel.isLoggingIn {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Waiting for browser…")
                                }
                            } else {
                                Label("Sign in with Claude", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoggingIn)
                        if viewModel.isLoggingIn {
                            Button("Cancel") { viewModel.cancelLogin() }
                        }
                    }
                } header: {
                    Text("Sign in")
                }

                Section {
                    Text("If sign-in doesn't work, paste your existing Claude Code access token instead (it has the required user:profile scope). This command copies it to your clipboard:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top) {
                        Text(Self.tokenCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.tokenCommand, forType: .string)
                        }
                    }
                    TextField("sk-ant-oat01-…", text: $token, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .font(.system(.body, design: .monospaced))
                    Button("Save & connect") { viewModel.loginWithToken(token) }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Or paste a token")
                }

                if let error = viewModel.loginError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Picker("Refresh every", selection: $settings.settings.refreshMinutes) {
                    ForEach(Settings.refreshOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
            }

            Section("Notifications") {
                Toggle("Notify near limit", isOn: $settings.settings.notifyAtHighUsage)
                Picker("Alert at", selection: $settings.settings.notifyThreshold) {
                    ForEach(Settings.thresholdOptions, id: \.self) { Text(verbatim: "\($0)%").tag($0) }
                }
                .disabled(!settings.settings.notifyAtHighUsage)
            }

            Section {
                Toggle("Auto-open new sessions", isOn: $settings.settings.autoOpenSession)
            } footer: {
                Text("Sends a tiny request about a minute after each 5-hour reset, so a fresh window opens immediately and keeps rolling. Uses minimal quota.")
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { Updater.shared.automaticallyChecksForUpdates },
                    set: { Updater.shared.automaticallyChecksForUpdates = $0 }))
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.settings.notifyAtHighUsage) { _, on in
            if on { UsageNotifier.requestAuthorization() }
        }
    }
}

private struct MenuBarSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Preview") { preview }
            Section {
                Picker("Show", selection: $settings.settings.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
                Picker("Style", selection: $settings.settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
                Toggle("Percentage", isOn: $settings.settings.menuBarShowPercent)
            }
        }
        .formStyle(.grouped)
    }

    private var preview: some View {
        let s = settings.settings
        let values = s.menuBarStyle == .combinedRing
            ? [UsageSnapshot.sample.sessionPercent, UsageSnapshot.sample.weeklyPercent]
            : s.menuBarMetric.values(.sample)
        return HStack {
            Spacer()
            Image(nsImage: StatusItemRenderer.image(values: values,
                                                    style: s.menuBarStyle,
                                                    showPercent: s.menuBarShowPercent))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.85), in: Capsule())
            Spacer()
        }
    }
}

private struct DisplaySettings: View {
    @Bindable private var settings = AppSettings.shared
    private let viewModel = UsageViewModel.shared

    /// The models to offer: whatever the account currently reports, plus the
    /// ones we know of — so a limit can be switched on before it first appears.
    private var modelKeys: [String] {
        let reported = viewModel.snapshot?.models.map(\.key) ?? []
        return ModelUsage.sorted(Set(reported + ModelUsage.knownOrder)
            .map { ModelUsage(key: $0, percent: 0, resetsAt: nil) }).map(\.key)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show per-model limits & spend", isOn: $settings.settings.showSecondary)
                Picker("Reset display", selection: $settings.settings.resetDisplay) {
                    ForEach(ResetFormat.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
            } header: {
                Text("Menu panel")
            } footer: {
                Text("These apply to the menu panel. Each widget is configured separately — right-click it and choose Edit Widget. Weekday and Date include the day for the weekly window.")
            }

            Section {
                ForEach(modelKeys, id: \.self) { key in
                    Toggle(isOn: modelBinding(key)) {
                        HStack(spacing: 6) {
                            Circle().fill(ModelUsage(key: key, percent: 0, resetsAt: nil).tint)
                                .frame(width: 8, height: 8)
                            Text(verbatim: ModelUsage(key: key, percent: 0, resetsAt: nil).displayName)
                            if viewModel.snapshot != nil, !reports(key) {
                                Text("not reported yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!settings.settings.showSecondary)
                }
                Toggle("Extra usage (spend)", isOn: $settings.settings.showSpend)
                    .disabled(!settings.settings.showSecondary)
            } header: {
                Text("Weekly limits per model")
            } footer: {
                Text("Anthropic reports a separate weekly window per model. Models your account doesn't have yet stay hidden until they appear — they then show up automatically.")
            }

            Section("Preview") { preview }
        }
        .formStyle(.grouped)
    }

    private func reports(_ key: String) -> Bool {
        viewModel.snapshot?.models.contains { $0.key == key } ?? false
    }

    private func modelBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !settings.settings.hiddenModels.contains(key) },
            set: { on in
                if on { settings.settings.hiddenModels.remove(key) }
                else { settings.settings.hiddenModels.insert(key) }
            }
        )
    }

    private var preview: some View {
        let snapshot = UsageSnapshot.sample
        let fmt = settings.settings.resetDisplay
        return VStack(alignment: .leading, spacing: 10) {
            UsageBar(title: "Session", percent: snapshot.sessionPercent,
                     resetsAt: snapshot.sessionResetsAt, resetFormat: fmt)
            UsageBar(title: "Weekly", percent: snapshot.weeklyPercent,
                     resetsAt: snapshot.weeklyResetsAt, resetFormat: fmt)
            ForEach(snapshot.visibleModels(settings.settings)) { model in
                UsageBar(title: "\(model.displayName)", percent: model.percent,
                         resetsAt: model.resetsAt, resetFormat: fmt)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AboutSettings: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let repo = URL(string: "https://github.com/Julian3521/ClaudeUsage")!

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("Claude Usage").font(.title2.bold())
            Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
            Link("github.com/Julian3521/ClaudeUsage", destination: repo)
            Text("Not affiliated with Anthropic.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
