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

            Section("Menu bar") {
                Picker("Show", selection: $appSettings.settings.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
                Toggle("Progress bar", isOn: $appSettings.settings.menuBarShowBar)
                Toggle("Percentage", isOn: $appSettings.settings.menuBarShowPercent)
            }

            Section("Widget & menu") {
                Toggle("Show Opus weekly limit (when present)",
                       isOn: $appSettings.settings.showOpus)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
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
                if appSettings.settings.showOpus, let opus = s.opusPercent {
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
