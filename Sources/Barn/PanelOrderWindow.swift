// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import BarnCore

/// Sets the order the panel lists apps in: drag rows about, or Sort A–Z to go
/// back to alphabetical, which is what the panel does until told otherwise.
///
/// A table rather than a menu, because rows have to be draggable and a menu
/// cannot do that. Changes apply as they are made: there is nothing here worth
/// a Save button, and a cancelled dialog would only raise the question of what
/// "cancel" undoes.
final class PanelOrderWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    /// The drag payload is the row index; the list is small and never reordered
    /// from outside this window, so there is nothing to gain from an identifier.
    private static let rowType = NSPasteboard.PasteboardType("com.nicholaspsmith.Barn.panelRow")

    /// Called with the new order of keys; empty means alphabetical.
    private let onChange: ([String]) -> Void
    private let table = NSTableView()
    private var apps: [PanelApp] = []

    init(onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Panel Order"
        window.minSize = NSSize(width: 300, height: 260)
        super.init(window: window)
        window.center()
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameter apps: already in the order the panel shows them.
    func show(apps: [PanelApp]) {
        self.apps = apps
        table.reloadData()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let caption = NSTextField(wrappingLabelWithString:
            "Drag to set the order the barn lists its apps in. "
            + "Apps that start later take their alphabetical place after these.")
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 24
        table.style = .inset
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([Self.rowType])
        table.draggingDestinationFeedbackStyle = .gap

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = table

        let sort = NSButton(title: "Sort A–Z", target: self, action: #selector(sortAlphabetically))
        sort.bezelStyle = .rounded

        for view in [caption, scroll, sort] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            caption.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            caption.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),

            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: sort.topAnchor, constant: -12),

            sort.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            sort.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            // Nothing inside has an intrinsic width, so the window needs a size
            // of its own to keep. minSize only limits dragging, not layout.
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
    }

    // MARK: - Rows

    func numberOfRows(in tableView: NSTableView) -> Int { apps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = apps[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = app.icon
        icon.imageScaling = .scaleProportionallyDown
        let label = NSTextField(labelWithString: app.name)
        label.lineBreakMode = .byTruncatingTail
        for view in [icon, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = icon
        cell.textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func sortAlphabetically() {
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        table.reloadData()
        onChange([])
    }

    // MARK: - Dragging

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Only between rows: dropping *on* a row would mean nesting, which this
        // list has no concept of.
        dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let text = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.rowType),
              let from = Int(text), apps.indices.contains(from)
        else { return false }

        let moved = apps.remove(at: from)
        // Removing the row first shifts every later index down by one.
        let destination = from < row ? row - 1 : row
        apps.insert(moved, at: min(max(destination, 0), apps.count))

        table.reloadData()
        onChange(apps.map(\.key))
        return true
    }
}
