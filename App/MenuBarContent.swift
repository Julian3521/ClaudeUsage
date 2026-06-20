import SwiftUI
import AppKit

/// Renders the menu-bar item: an optional progress bar (drawn as an image so it
/// renders reliably in the status bar) and/or the percentage text.
struct MenuBarContent: View {
    let values: [Double]
    let showBar: Bool
    let showPercent: Bool

    var body: some View {
        if !showBar && !showPercent {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
        } else {
            HStack(spacing: 4) {
                if showBar {
                    Image(nsImage: MenuBarRenderer.image(for: values))
                }
                if showPercent {
                    Text(values.map { "\(Int($0.rounded()))%" }.joined(separator: " "))
                }
            }
        }
    }
}

enum MenuBarRenderer {
    /// Draws 1–2 stacked rounded progress bars with traffic-light fill colors.
    static func image(for values: [Double]) -> NSImage {
        let width: CGFloat = 24, barHeight: CGFloat = 5, gap: CGFloat = 3
        let count = max(1, values.count)
        let height = CGFloat(count) * barHeight + CGFloat(count - 1) * gap
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size)
        image.lockFocus()
        for (index, value) in values.enumerated() {
            let y = size.height - CGFloat(index + 1) * barHeight - CGFloat(index) * gap
            let track = NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: width, height: barHeight),
                                     xRadius: barHeight / 2, yRadius: barHeight / 2)
            NSColor(white: 0.5, alpha: 0.35).setFill()
            track.fill()

            let fraction = min(1, max(0, value / 100))
            let fillWidth = max(barHeight, width * fraction)
            let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: fillWidth, height: barHeight),
                                    xRadius: barHeight / 2, yRadius: barHeight / 2)
            color(for: value).setFill()
            fill.fill()
        }
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
