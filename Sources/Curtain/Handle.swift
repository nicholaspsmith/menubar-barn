import AppKit
import CurtainCore
import StatusItemKit

/// The visible control: a narrow status item showing which way the curtain is
/// drawn, carrying the menu.
///
/// Narrow on purpose. A status item only renders when its slot fits entirely
/// within the usable area, so the control has to be small enough to sit beside
/// the user's own icons — which is exactly why it cannot also be the curtain.
final class Handle {
    private let controller: StatusItemController

    init(controller: StatusItemController) {
        self.controller = controller
    }

    func draw(hidden: Bool, style: HandleStyle) {
        switch style {
        case .barn: controller.setIcon(Self.barn(open: !hidden))
        case .chevron: controller.setIcon(Self.chevron(pointingLeft: hidden))
        }
    }

    /// A small barn. Doors shut while the curtain is drawn, open — the doorway
    /// cut out so the bar shows through — while the icons are revealed. Same
    /// 18pt template canvas as the chevron, so switching styles moves nothing.
    private static func barn(open: Bool) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current else { return false }
            NSColor.black.set()
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 3, y: 2.5)); body.line(to: NSPoint(x: 3, y: 9))
            body.line(to: NSPoint(x: 5, y: 12.5)); body.line(to: NSPoint(x: 9, y: 15.5)); body.line(to: NSPoint(x: 13, y: 12.5))
            body.line(to: NSPoint(x: 15, y: 9)); body.line(to: NSPoint(x: 15, y: 2.5)); body.close()
            body.fill()
            // Doorway and hayloft window are holes: template tinting keys off alpha.
            ctx.compositingOperation = .destinationOut
            NSBezierPath(roundedRect: NSRect(x: 6.5, y: 2.5, width: 5, height: 6), xRadius: 0.6, yRadius: 0.6).fill()
            NSBezierPath(ovalIn: NSRect(x: 7.9, y: 10.2, width: 2.2, height: 2.2)).fill()
            ctx.compositingOperation = .sourceOver
            if !open {
                NSBezierPath(rect: NSRect(x: 7, y: 2.5, width: 4, height: 5.5)).fill()
                ctx.compositingOperation = .destinationOut
                let seam = NSBezierPath()
                seam.move(to: NSPoint(x: 9, y: 2.5)); seam.line(to: NSPoint(x: 9, y: 8))
                seam.lineWidth = 0.7; seam.stroke()
                ctx.compositingOperation = .sourceOver
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A chevron stroked as a path, matching how `MeterIcon` draws across these
    /// apps. Points the way the icons will go when clicked.
    private static func chevron(pointingLeft: Bool) -> NSImage {
        let side: CGFloat = 18
        let arm: CGFloat = 4.5
        let rise: CGFloat = 4.5

        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let midX = rect.midX
            let midY = rect.midY
            let path = NSBezierPath()
            if pointingLeft {
                path.move(to: NSPoint(x: midX + arm / 2, y: midY + rise))
                path.line(to: NSPoint(x: midX - arm / 2, y: midY))
                path.line(to: NSPoint(x: midX + arm / 2, y: midY - rise))
            } else {
                path.move(to: NSPoint(x: midX - arm / 2, y: midY + rise))
                path.line(to: NSPoint(x: midX + arm / 2, y: midY))
                path.line(to: NSPoint(x: midX - arm / 2, y: midY - rise))
            }
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // Template tinting keys off alpha, so the ink colour is irrelevant.
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
