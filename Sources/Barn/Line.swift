// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

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

    /// The pre-27 floor; the owner passes `BarnGeometry.unhostedLineWidth`,
    /// which grows with the display, since on a wide one a 2000pt line stops
    /// short of the edge. Precision would be pointless: overshooting only
    /// pushes hidden icons further off-screen, and the app cannot measure its
    /// own position reliably anyway — a status item's window frame disagrees
    /// with its true screen position by hundreds of points, because these
    /// items are hosted by Control Center rather than by us. On macOS 27 the
    /// agent ejects an item this wide outright, so the owner computes a width
    /// per bar and passes it in.
    static let hiddenWidth: CGFloat = BarnGeometry.unhostedLineFloor

    /// Readable through the agent's tree, so the line can be told from the
    /// handle by name rather than by guessing from widths.
    static let identifier = "BarnLine"
    /// The second line macOS 27 needs, immediately left of the first. See
    /// docs/superpowers/specs/2026-09-17-two-lines-and-collapse-design.md.
    static let secondIdentifier = "BarnLineB"

    let identifier: String

    init(autosaveName: String = "BarnLine", identifier: String = Line.identifier) {
        self.identifier = identifier
        item = NSStatusBar.system.statusItem(withLength: BarnGeometry.showWidth)
        item.autosaveName = autosaveName
        item.button?.title = ""
        item.button?.image = nil
        item.button?.setAccessibilityIdentifier(identifier)
    }

    var width: CGFloat { item.length }

    func hide() { hide(width: Self.hiddenWidth) }

    func hide(width: CGFloat) { if item.length != width { item.length = width } }

    func show() { if item.length != BarnGeometry.showWidth { item.length = BarnGeometry.showWidth } }
}
