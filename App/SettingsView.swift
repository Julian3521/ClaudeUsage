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
            WidgetSettings()
                .tabItem { Label("Widget", systemImage: "square.grid.2x2") }
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
                Section("Sign in") {
                    Text("Uses your existing Claude Code login (it already has the required user:profile scope). Everything stays local — only the usage request goes to Anthropic.")
                        .font(.callout)
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
                    if let error = viewModel.loginError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Save & connect") { viewModel.loginWithToken(token) }
                        .buttonStyle(.borderedProminent)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                Toggle("Progress bar", isOn: $settings.settings.menuBarShowBar)
                Toggle("Percentage", isOn: $settings.settings.menuBarShowPercent)
            }
        }
        .formStyle(.grouped)
    }

    private var preview: some View {
        let s = settings.settings
        return HStack {
            Spacer()
            Image(nsImage: StatusItemRenderer.image(values: s.menuBarMetric.values(.sample),
                                                    showBar: s.menuBarShowBar,
                                                    showPercent: s.menuBarShowPercent))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.85), in: Capsule())
            Spacer()
        }
    }
}

private struct WidgetSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show Opus, Sonnet & spend", isOn: $settings.settings.showSecondary)
                Toggle("Show reset as clock time", isOn: $settings.settings.showAbsoluteReset)
            }
            Section("Preview") { preview }
        }
        .formStyle(.grouped)
    }

    private var preview: some View {
        let snapshot = UsageSnapshot.sample
        let absolute = settings.settings.showAbsoluteReset
        return VStack(alignment: .leading, spacing: 10) {
            UsageBar(title: "Session", percent: snapshot.sessionPercent,
                     resetsAt: snapshot.sessionResetsAt, absoluteReset: absolute)
            UsageBar(title: "Weekly", percent: snapshot.weeklyPercent,
                     resetsAt: snapshot.weeklyResetsAt, absoluteReset: absolute)
            if settings.settings.showSecondary, let opus = snapshot.opusPercent {
                UsageBar(title: "Opus", percent: opus,
                         resetsAt: snapshot.opusResetsAt, absoluteReset: absolute)
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
