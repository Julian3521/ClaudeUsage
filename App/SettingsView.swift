import SwiftUI

struct SettingsView: View {
    @Bindable private var appSettings = AppSettings.shared

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show", selection: $appSettings.settings.menuBarMetric) {
                    ForEach(MenuBarMetric.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
                Picker("Style", selection: $appSettings.settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
            }
            Section("Widget & menu") {
                Toggle("Show Opus weekly limit (when present)",
                       isOn: $appSettings.settings.showOpus)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
