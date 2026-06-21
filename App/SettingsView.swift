import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            MenuBarSettings()
                .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }
            WidgetSettings()
                .tabItem { Label("Widget", systemImage: "square.grid.2x2") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 380)
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let viewModel = UsageViewModel.shared

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

            if viewModel.state != .loggedOut {
                Section("Account") {
                    Button("Copy raw response") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.rawJSON, forType: .string)
                    }
                    Button("Sign out", role: .destructive) { viewModel.logout() }
                }
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
                                                    showPercent: s.menuBarShowPercent,
                                                    warning: false))
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
