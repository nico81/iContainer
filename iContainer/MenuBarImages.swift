import AppKit

enum MenuBarImages {
    static func statusDot(isRunning: Bool) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()

        let color = isRunning
            ? NSColor.systemGreen
            : NSColor.systemRed
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let strokeRect = NSRect(x: 0.75, y: 0.75, width: 8.5, height: 8.5)
        let strokePath = NSBezierPath(ovalIn: strokeRect)
        strokePath.lineWidth = 1
        strokePath.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
