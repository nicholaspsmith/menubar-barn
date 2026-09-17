import AppKit
import BarnCore

/// The barn wall proper: an invisible status item whose *width* pushes its
/// left-hand neighbours off the display.
///
/// It draws nothing, and it cannot: macOS renders a status item only when its
/// slot fits entirely inside the usable area (right of the notch). This one is
/// hundreds of points wide by design, so it always overlaps the notch and is
/// always invisible — measured by filling it with 80 glyphs and seeing none of
/// them. That is fine. Occupying width is its whole job; `Handle` is the part
/// the user sees and clicks.
final class Line {
    private let item: NSStatusItem

    /// Wide enough to push any realistic block clear off the left edge, far
    /// below the ~5012pt clamp. Precision would be pointless: overshooting only
    /// pushes hidden icons further off-screen, and the app cannot measure its own
    /// position reliably anyway — a status item's window frame disagrees with its
    /// true screen position by hundreds of points, because these items are hosted
    /// by Control Center rather than by us.
    ///
    /// That is the pre-27 width. On macOS 27 the agent ejects an item this wide
    /// outright, so the owner computes a width per bar and passes it in.
    static let hiddenWidth: CGFloat = 2000

    /// Readable through the agent's tree, so the line can be told from the
    /// handle by name rather than by guessing from widths.
    static let identifier = "BarnLine"

    init() {
        item = NSStatusBar.system.statusItem(withLength: BarnGeometry.showWidth)
        item.autosaveName = "BarnLine"
        item.button?.title = ""
        item.button?.image = nil
        item.button?.setAccessibilityIdentifier(Self.identifier)
    }

    var width: CGFloat { item.length }

    func hide() { hide(width: Self.hiddenWidth) }

    func hide(width: CGFloat) { if item.length != width { item.length = width } }

    func show() { if item.length != BarnGeometry.showWidth { item.length = BarnGeometry.showWidth } }
}
