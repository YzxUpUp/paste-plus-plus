import AppKit

@MainActor
enum HistoryStatusIcon {
    static func make(count: Int) -> NSImage {
        let symbol = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        let digits = NSAttributedString(string: String(count), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.black
        ])
        let symbolSize = symbol?.size ?? .zero
        let digitStart = ceil(symbolSize.width) + 1
        let size = NSSize(width: digitStart + ceil(digits.size().width), height: 19)
        let image = NSImage(size: size, flipped: false) { _ in
            symbol?.draw(at: NSPoint(x: 0, y: floor((size.height - symbolSize.height) / 2)),
                         from: .zero, operation: .sourceOver, fraction: 1)
            digits.draw(at: NSPoint(x: digitStart, y: 0))
            return true
        }
        image.isTemplate = true
        return image
    }
}
