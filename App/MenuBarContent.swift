import SwiftUI
import AppKit

/// Renders the menu-bar item. For each value it shows an optional progress bar
/// (drawn as an image so it renders reliably in the status bar) next to its
/// percentage — so "Session + weekly" appears as two bar+percent groups.
struct MenuBarContent: View {
    let values: [Double]
    let showBar: Bool
    let showPercent: Bool

    var body: some View {
        if !showBar && !showPercent {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
        } else {
            HStack(spacing: 7) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    HStack(spacing: 3) {
                        if showBar {
                            Image(nsImage: MenuBarRenderer.bar(for: value))
                        }
                        if showPercent {
                            Text("\(Int(value.rounded()))%")
                        }
                    }
                }
            }
        }
    }
}

enum MenuBarRenderer {
    /// Draws a single rounded progress bar with a traffic-light fill color.
    static func bar(for value: Double) -> NSImage {
        let width: CGFloat = 22, height: CGFloat = 6
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size)
        image.lockFocus()
        let track = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                                 xRadius: height / 2, yRadius: height / 2)
        NSColor(white: 0.5, alpha: 0.35).setFill()
        track.fill()

        let fraction = min(1, max(0, value / 100))
        let fillWidth = max(height, width * fraction)
        let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: fillWidth, height: height),
                                xRadius: height / 2, yRadius: height / 2)
        color(for: value).setFill()
        fill.fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func color(for percent: Double) -> NSColor {
        switch percent {
        case ..<60: return .systemGreen
        case ..<85: return .systemOrange
        default: return .systemRed
        }
    }
}
