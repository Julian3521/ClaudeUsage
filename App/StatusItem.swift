import AppKit
import SwiftUI
import Observation
import WidgetKit

/// Renders the full menu-bar content (1–2 groups drawn as a bar, a ring, or text,
/// coloured by severity, with an optional warning) into a single NSImage.
enum StatusItemRenderer {
    static func image(values: [Double], style: MenuBarStyle, showPercent: Bool,
                      rateLimited: Bool = false) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let height: CGFloat = 22
        let barW: CGFloat = 22, barH: CGFloat = 6, innerGap: CGFloat = 3, groupGap: CGFloat = 8
        let ringD: CGFloat = 17, ringLW: CGFloat = 2.6
        let texts = values.map { "\(Int($0.rounded()))%" as NSString }
        func textW(_ t: NSString) -> CGFloat { t.size(withAttributes: [.font: font]).width }

        // Native red "rate limited" glyph, drawn first when active.
        let warnSymbol: NSImage? = rateLimited ? NSImage(
            systemSymbolName: "exclamationmark.circle.fill",
            accessibilityDescription: "Rate limited"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                .applying(.init(paletteColors: [.systemRed]))
        ) : nil
        let warnW = warnSymbol.map { $0.size.width + 5 } ?? 0

        let bare = (style == .none && !showPercent)   // nothing to show → a dot
        var width = warnW
        if style == .combinedRing {
            width += ringD
        } else if bare {
            width += 18
        } else {
            for (i, t) in texts.enumerated() {
                if i > 0 { width += groupGap }
                switch style {
                case .bar:  width += barW + (showPercent ? innerGap + textW(t) : 0)
                case .ring: width += ringD                       // percent sits inside
                case .none: width += showPercent ? textW(t) : 0
                case .combinedRing: break
                }
            }
        }
        let size = NSSize(width: ceil(max(width, 10)), height: height)

        let image = NSImage(size: size)
        image.lockFocus()
        var x: CGFloat = 0

        if let warnSymbol {
            let s = warnSymbol.size
            warnSymbol.draw(at: NSPoint(x: 0, y: (height - s.height) / 2),
                            from: .zero, operation: .sourceOver, fraction: 1)
            x += warnW
        }

        if style == .combinedRing {
            drawCombinedRing(session: values.first ?? 0,
                             weekly: values.count > 1 ? values[1] : 0,
                             x: x, height: height, diameter: ringD, lineWidth: ringLW,
                             showPercent: showPercent)
        } else if bare {
            let dot = NSBezierPath(ovalIn: NSRect(x: x + 4, y: height/2 - 4, width: 8, height: 8))
            NSColor.secondaryLabelColor.setFill(); dot.fill()
        } else {
            for (i, value) in values.enumerated() {
                if i > 0 { x += groupGap }
                let color = nsColor(for: value)
                switch style {
                case .combinedRing:
                    break
                case .bar:
                    let y = (height - barH) / 2
                    NSColor(white: 0.5, alpha: 0.35).setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: barH),
                                 xRadius: barH/2, yRadius: barH/2).fill()
                    let fw = max(barH, barW * min(1, max(0, value / 100)))
                    color.setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: fw, height: barH),
                                 xRadius: barH/2, yRadius: barH/2).fill()
                    x += barW
                    if showPercent {
                        x += innerGap
                        drawText(texts[i], at: &x, height: height, font: font, color: color)
                    }
                case .ring:
                    drawRing(value: value, x: x, height: height,
                             diameter: ringD, lineWidth: ringLW, color: color, showPercent: showPercent)
                    x += ringD
                case .none:
                    if showPercent { drawText(texts[i], at: &x, height: height, font: font, color: color) }
                }
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawText(_ t: NSString, at x: inout CGFloat, height: CGFloat,
                                 font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let ts = t.size(withAttributes: attrs)
        t.draw(at: NSPoint(x: x, y: (height - ts.height) / 2), withAttributes: attrs)
        x += ts.width
    }

    /// A circular progress ring; when `showPercent`, the value sits inside it.
    private static func drawRing(value: Double, x: CGFloat, height: CGFloat,
                                 diameter: CGFloat, lineWidth: CGFloat,
                                 color: NSColor, showPercent: Bool) {
        let center = NSPoint(x: x + diameter / 2, y: height / 2)
        let r = (diameter - lineWidth) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor(white: 0.5, alpha: 0.35).setStroke(); track.stroke()

        let frac = min(1, max(0, value / 100))
        if frac > 0 {
            let prog = NSBezierPath()
            prog.appendArc(withCenter: center, radius: r,
                           startAngle: 90, endAngle: 90 - 360 * frac, clockwise: true)
            prog.lineWidth = lineWidth
            prog.lineCapStyle = .round
            color.setStroke(); prog.stroke()
        }
        if showPercent {
            let n = "\(Int(value.rounded()))" as NSString
            let f = NSFont.systemFont(ofSize: value >= 100 ? 7 : 8.5, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
            let ts = n.size(withAttributes: attrs)
            n.draw(at: NSPoint(x: center.x - ts.width / 2, y: center.y - ts.height / 2), withAttributes: attrs)
        }
    }

    /// One ring with both values overlaid: session (blue) + weekly (orange) on the
    /// same track. The higher arc is drawn first and the lower on top, so the higher
    /// value's colour forms the protruding tail. The centre number is the higher of
    /// the two, in that metric's colour.
    private static func drawCombinedRing(session: Double, weekly: Double, x: CGFloat,
                                         height: CGFloat, diameter: CGFloat,
                                         lineWidth: CGFloat, showPercent: Bool) {
        let center = NSPoint(x: x + diameter / 2, y: height / 2)
        let r = (diameter - lineWidth) / 2
        let blue = NSColor.systemBlue, orange = NSColor.systemOrange

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor(white: 0.5, alpha: 0.35).setStroke(); track.stroke()

        func arc(_ value: Double, _ color: NSColor) {
            let frac = min(1, max(0, value / 100))
            guard frac > 0 else { return }
            let p = NSBezierPath()
            p.appendArc(withCenter: center, radius: r,
                        startAngle: 90, endAngle: 90 - 360 * frac, clockwise: true)
            p.lineWidth = lineWidth
            p.lineCapStyle = .round
            color.setStroke(); p.stroke()
        }
        // Higher first, lower on top → the higher value's colour stays visible as the tail.
        if session >= weekly { arc(session, blue); arc(weekly, orange) }
        else { arc(weekly, orange); arc(session, blue) }

        if showPercent {
            let higher = max(session, weekly)
            let color = session >= weekly ? blue : orange
            let n = "\(Int(higher.rounded()))" as NSString
            let f = NSFont.systemFont(ofSize: higher >= 100 ? 7 : 8.5, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
            let ts = n.size(withAttributes: attrs)
            n.draw(at: NSPoint(x: center.x - ts.width / 2, y: center.y - ts.height / 2), withAttributes: attrs)
        }
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

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            MenuContentView(viewModel: viewModel)
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
            let values = settings.menuBarStyle == .combinedRing
                ? [snapshot.sessionPercent, snapshot.weeklyPercent]
                : settings.menuBarMetric.values(snapshot)
            button.image = StatusItemRenderer.image(
                values: values,
                style: settings.menuBarStyle,
                showPercent: settings.menuBarShowPercent,
                rateLimited: viewModel.isRateLimited)
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
            // Opening the menu is a good moment to freshen data and push the latest
            // snapshot to the widgets so they don't trail the live menu-bar reading.
            WidgetCenter.shared.reloadAllTimelines()
            Task { await viewModel.refresh() }
        }
    }
}
