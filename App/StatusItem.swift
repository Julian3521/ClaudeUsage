import AppKit
import SwiftUI
import Observation

/// Renders the full menu-bar content (1–2 bar+percent groups, colored by
/// severity, optional warning) into a single NSImage for an NSStatusItem.
enum StatusItemRenderer {
    static func image(values: [Double], showBar: Bool, showPercent: Bool, warning: Bool) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let height: CGFloat = 22
        let barW: CGFloat = 22, barH: CGFloat = 6, innerGap: CGFloat = 3, groupGap: CGFloat = 8
        let warnW: CGFloat = warning ? 16 : 0
        let texts = values.map { "\(Int($0.rounded()))%" as NSString }

        var width = warnW
        if !showBar && !showPercent {
            width += 18
        } else {
            for (i, t) in texts.enumerated() {
                if i > 0 { width += groupGap }
                if showBar { width += barW }
                if showBar && showPercent { width += innerGap }
                if showPercent { width += t.size(withAttributes: [.font: font]).width }
            }
        }
        let size = NSSize(width: ceil(max(width, 10)), height: height)

        let image = NSImage(size: size)
        image.lockFocus()
        var x: CGFloat = 0

        if warning {
            let r = NSRect(x: 1, y: (height - 12) / 2, width: 12, height: 11)
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: r.midX, y: r.maxY))
            tri.line(to: NSPoint(x: r.minX, y: r.minY))
            tri.line(to: NSPoint(x: r.maxX, y: r.minY))
            tri.close()
            NSColor.systemOrange.setFill(); tri.fill()
            x += warnW
        }

        if !showBar && !showPercent {
            let dot = NSBezierPath(ovalIn: NSRect(x: x + 4, y: height/2 - 4, width: 8, height: 8))
            NSColor.secondaryLabelColor.setFill(); dot.fill()
        } else {
            for (i, value) in values.enumerated() {
                if i > 0 { x += groupGap }
                let color = nsColor(for: value)
                if showBar {
                    let y = (height - barH) / 2
                    NSColor(white: 0.5, alpha: 0.35).setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: barH),
                                 xRadius: barH/2, yRadius: barH/2).fill()
                    let fw = max(barH, barW * min(1, max(0, value / 100)))
                    color.setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: fw, height: barH),
                                 xRadius: barH/2, yRadius: barH/2).fill()
                    x += barW
                    if showPercent { x += innerGap }
                }
                if showPercent {
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let ts = texts[i].size(withAttributes: attrs)
                    texts[i].draw(at: NSPoint(x: x, y: (height - ts.height) / 2), withAttributes: attrs)
                    x += ts.width
                }
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func nsColor(for percent: Double) -> NSColor {
        switch percent {
        case ..<60: return .systemGreen
        case ..<85: return .systemOrange
        default: return .systemRed
        }
    }
}

/// Owns the menu-bar status item + popover + login window, and keeps the status
/// item image in sync with the view model and settings via Observation.
@MainActor
final class StatusItemController {
    private let viewModel: UsageViewModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var loginWindow: NSWindow?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            MenuContentView(viewModel: viewModel,
                            onOpenLogin: { [weak self] in self?.showLogin() })
        )

        observe()
    }

    /// Re-render the status item whenever any observed property changes.
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let settings = AppSettings.shared.settings
        if let snapshot = viewModel.snapshot {
            button.image = StatusItemRenderer.image(
                values: settings.menuBarMetric.values(snapshot),
                showBar: settings.menuBarShowBar,
                showPercent: settings.menuBarShowPercent,
                warning: viewModel.lastFetchFailed)
            button.toolTip = "Claude Usage"
        } else {
            let symbol = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                                 accessibilityDescription: "Claude Usage")
            symbol?.isTemplate = true
            button.image = symbol
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showLogin() {
        popover.performClose(nil)
        viewModel.prepareLogin()
        if loginWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = String(localized: "Sign in to Claude")
            window.isReleasedWhenClosed = false
            window.center()
            window.contentViewController = NSHostingController(rootView:
                LoginWindowView(viewModel: viewModel, onClose: { [weak self] in
                    self?.loginWindow?.close()
                }))
            loginWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        loginWindow?.makeKeyAndOrderFront(nil)
    }
}
