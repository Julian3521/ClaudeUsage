import AppIntents
import WidgetKit

/// Per-widget settings, editable via right-click → Edit Widget. Mirrors the app's
/// Display settings but each placed widget can choose its own.
struct ClaudeWidgetConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Claude Usage"
    static let description = IntentDescription("Choose what this widget shows.")

    @Parameter(title: "Show Opus, Sonnet & spend", default: true)
    var showSecondary: Bool

    @Parameter(title: "Reset display", default: .relative)
    var resetDisplay: ResetFormat

    init() {}
    init(showSecondary: Bool, resetDisplay: ResetFormat) {
        self.showSecondary = showSecondary
        self.resetDisplay = resetDisplay
    }
}
