import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettings()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            BudgetSettings()
                .tabItem { Label("Budget", systemImage: "calendar") }
            MenuBarSettings()
                .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }
            DisplaySettings()
                .tabItem { Label("Menu panel", systemImage: "rectangle.grid.1x2") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 430)
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
    private let viewModel = UsageViewModel.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Picker("Refresh every", selection: $settings.settings.refreshMinutes) {
                    ForEach(Settings.refreshOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
            }

            Section {
                Toggle("Notify near limit", isOn: $settings.settings.notifyAtHighUsage)
                Picker("Alert at", selection: $settings.settings.notifyThreshold) {
                    ForEach(Settings.thresholdOptions, id: \.self) { Text(verbatim: "\($0)%").tag($0) }
                }
                .disabled(!settings.settings.notifyAtHighUsage)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Daily budget warnings are under Budget.")
            }

            // Plans without a 5-hour window (Max 20x) have no sessions to open.
            if viewModel.snapshot?.hasSession ?? true {
                Section {
                    Toggle("Auto-open new sessions", isOn: $settings.settings.autoOpenSession)
                } header: {
                    Text("Session windows")
                } footer: {
                    Text("Sends a tiny request about a minute after each 5-hour reset, so a fresh window opens immediately and keeps rolling. Uses minimal quota.")
                }
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

private struct BudgetSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let viewModel = UsageViewModel.shared

    private enum Kind: Hashable { case off, fixed, flexible }

    /// Off / fixed / flexible as one segmented choice; the day count for a
    /// fixed budget sits in its own picker below.
    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch settings.settings.dailyBudget {
                case .off: .off
                case .even: .fixed
                case .flexible: .flexible
                }
            },
            set: { kind in
                switch kind {
                case .off: settings.settings.dailyBudget = .off
                case .fixed: if case .even = settings.settings.dailyBudget {} else {
                    settings.settings.dailyBudget = .even(days: 7)
                }
                case .flexible: settings.settings.dailyBudget = .flexible
                }
            })
    }

    private var days: Binding<Int> {
        Binding(
            get: { if case .even(let days) = settings.settings.dailyBudget { days } else { 7 } },
            set: { settings.settings.dailyBudget = .even(days: $0) })
    }

    private var explanation: LocalizedStringKey {
        switch settings.settings.dailyBudget {
        case .off:
            "Splits the weekly limit into a daily allowance, so one long day can't use up the whole week."
        case .even:
            "The same share every day; unused budget doesn't carry over. Counts from midnight."
        case .flexible:
            "What's left of the week, spread over the days until it resets — a quiet day leaves more for the next. Counts from midnight."
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Daily budget", selection: kind) {
                    Text("Off").tag(Kind.off)
                    Text("Fixed").tag(Kind.fixed)
                    Text("Flexible").tag(Kind.flexible)
                }
                .pickerStyle(.segmented)
                if case .even = settings.settings.dailyBudget {
                    Picker("Spread the week over", selection: days) {
                        ForEach(Settings.dailyBudgetDays, id: \.self) { days in
                            (Text("\(days) days") + Text(verbatim: " · \(Int((100 / Double(days)).rounded()))%"))
                                .tag(days)
                        }
                    }
                }
            } footer: {
                Text(explanation)
            }

            if settings.settings.dailyBudget != .off {
                // Same reading as the panel: the budget as a share of the week,
                // used and left as shares of the budget.
                Section("Today") {
                    if let daily = viewModel.dailyBudget {
                        LabeledContent("Budget") {
                            Text("\(Self.percent(daily.budget)) of weekly limit")
                        }
                        LabeledContent("Used", value: Self.percent(daily.percent))
                        LabeledContent("Left", value: Self.percent(daily.remainingPercent))
                    } else {
                        Text("Shown once usage has been loaded.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Warn when nearly or fully used up", isOn: $settings.settings.notifyDailyBudget)
                } footer: {
                    Text("One notification at \(Int(UsageNotifier.dailyWarningShare * 100))% of the day's budget, another when it's used up.")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.settings.dailyBudget) { _, mode in
            if mode != .off, settings.settings.notifyDailyBudget { UsageNotifier.requestAuthorization() }
        }
        .onChange(of: settings.settings.notifyDailyBudget) { _, on in
            if on { UsageNotifier.requestAuthorization() }
        }
    }

    private static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}

private struct MenuBarSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let viewModel = UsageViewModel.shared

    private var hasSession: Bool { viewModel.snapshot?.hasSession ?? true }

    var body: some View {
        Form {
            Section("Preview") { preview }
            Section {
                // Bound to what the menu bar really shows, so a choice the plan
                // can't back never sits in the picker as if it applied.
                Picker("Show", selection: Binding(
                    get: { settings.settings.shownMetric(hasSession: hasSession) },
                    set: { settings.settings.menuBarMetric = $0 })) {
                    ForEach(settings.settings.menuBarMetrics(hasSession: hasSession), id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
                Picker("Style", selection: Binding(
                    get: { settings.settings.shownStyle(hasSession: hasSession) },
                    set: { settings.settings.menuBarStyle = $0 })) {
                    ForEach(MenuBarStyle.allCases.filter { hasSession || $0 != .combinedRing }, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
                Toggle("Percentage", isOn: $settings.settings.menuBarShowPercent)
            } footer: {
                if !hasSession {
                    Text("Your plan has no 5-hour window, so the session options are hidden.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var preview: some View {
        let s = settings.settings
        let sample = UsageSnapshot.sample.withSession(hasSession)
        let style = s.shownStyle(hasSession: hasSession)
        let values = style == .combinedRing
            ? [sample.sessionPercent, sample.weeklyPercent]
            : s.shownMetric(hasSession: hasSession).values(sample, today: .sample)
        return HStack {
            Spacer()
            Image(nsImage: StatusItemRenderer.image(values: values,
                                                    style: style,
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

    /// The models the account reports; before the first fetch, the ones we
    /// know of. Anything new shows up by default once it's reported.
    private var modelKeys: [String] {
        let reported = viewModel.snapshot?.models.map(\.key) ?? []
        return reported.isEmpty ? ModelUsage.knownOrder : reported
    }

    var body: some View {
        Form {
            Section {
                ForEach(modelKeys, id: \.self) { key in
                    let model = ModelUsage(key: key, percent: 0, resetsAt: nil)
                    Toggle(isOn: modelBinding(key)) {
                        HStack(spacing: 6) {
                            Circle().fill(model.tint).frame(width: 8, height: 8)
                            Text("Weekly · \(model.displayName)")
                        }
                    }
                }
                Toggle("Extra usage (spend)", isOn: $settings.settings.showSpend)
            } header: {
                Text("Shown in the panel")
            } footer: {
                Text("New models show up here once your account reports them.")
            }

            Section {
                Picker("Reset display", selection: $settings.settings.resetDisplay) {
                    ForEach(ResetFormat.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.label)).tag($0)
                    }
                }
            } footer: {
                Text("Widgets have their own options: right-click a widget and choose Edit Widget.")
            }

            Section("Preview") { preview }
        }
        .formStyle(.grouped)
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
        let hasSession = viewModel.snapshot?.hasSession ?? true
        let snapshot = UsageSnapshot.sample
        let fmt = settings.settings.resetDisplay
        return VStack(alignment: .leading, spacing: 10) {
            if settings.settings.dailyBudget != .off {
                DailyBudgetBar(budget: .sample, resetFormat: fmt)
            }
            if hasSession {
                UsageBar(title: "Session", percent: snapshot.sessionPercent,
                         resetsAt: snapshot.sessionResetsAt, resetFormat: fmt)
            }
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
