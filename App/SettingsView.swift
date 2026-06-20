import SwiftUI

struct SettingsView: View {
    @Bindable private var appSettings = AppSettings.shared

    var body: some View {
        Form {
            Section("Preview") {
                VStack(spacing: 14) {
                    menuBarPreview
                    widgetPreview
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $appSettings.launchAtLogin)
                Picker("Refresh every", selection: $appSettings.settings.refreshMinutes) {
                    ForEach(Settings.refreshOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
                Toggle("Notify near limit", isOn: $appSettings.settings.notifyAtHighUsage)
            }

            Section("Menu bar") {
                Picker("Show", selection: $appSettings.settings.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
                Toggle("Progress bar", isOn: $appSettings.settings.menuBarShowBar)
                Toggle("Percentage", isOn: $appSettings.settings.menuBarShowPercent)
            }

            Section("Details") {
                Toggle("Show Opus, Sonnet & spend", isOn: $appSettings.settings.showSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onChange(of: appSettings.settings.notifyAtHighUsage) { _, on in
            if on { UsageNotifier.requestAuthorization() }
        }
    }

    private var menuBarPreview: some View {
        let settings = appSettings.settings
        return VStack(spacing: 4) {
            ZStack {
                Capsule().fill(.black.opacity(0.85))
                MenuBarContent(values: settings.menuBarMetric.values(.sample),
                               showBar: settings.menuBarShowBar,
                               showPercent: settings.menuBarShowPercent)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
            }
            .frame(height: 28)
            .fixedSize()
            Text("Menu bar").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var widgetPreview: some View {
        let s = UsageSnapshot.sample
        return VStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 10) {
                UsageBar(title: "Session", percent: s.sessionPercent, resetsAt: s.sessionResetsAt)
                UsageBar(title: "Weekly", percent: s.weeklyPercent, resetsAt: s.weeklyResetsAt)
                if appSettings.settings.showSecondary, let opus = s.opusPercent {
                    UsageBar(title: "Opus", percent: opus, resetsAt: s.opusResetsAt)
                }
            }
            .padding(12)
            .frame(width: 180)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            Text("Widget").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
