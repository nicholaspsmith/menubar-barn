// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// One slot as a single one of the agent's windows reports it.
///
/// `identifier` is the accessibility identifier of the status item's button.
/// Barn labels its own three items that way so the two lines and the handle
/// can be told apart without guessing from their widths — during the settle
/// they are all the same width, so widths cannot tell them apart at all.
public struct HostedSlotReading: Equatable, Sendable {
    public let pid: pid_t
    public let frame: ItemFrame
    public let identifier: String?

    public init(pid: pid_t, frame: ItemFrame, identifier: String?) {
        self.pid = pid
        self.frame = frame
        self.identifier = identifier
    }
}

/// `MenuBarAgent` publishes the bar as several accessibility windows, all of
/// them listing the same slots in the same places — but only one hands back
/// each app's status-item button. The rest answer with the owning
/// *application* element, which has no identifier at all, so a reader that
/// takes `windows.first` sees an anonymous bar and cannot find its own items
/// in it.
///
/// Measured 2026-09-22 on macOS 27: four windows, twelve children each;
/// window 1 carried the buttons, windows 0, 2 and 3 carried application
/// elements. Which index it is is not documented and not worth relying on, so
/// Barn reads the windows in turn and takes the first that names its items.
public enum HostedWindows {
    /// The one window to trust: the first that names the items belonging to
    /// `pid`, else the first that lists anything at all.
    ///
    /// Merging the windows looks tempting — they publish the same bar — but
    /// they are separate snapshots, and while the agent is reflowing they
    /// disagree. Measured 2026-09-24 mid-reflow: four windows gave four
    /// different positions for the same icons, and merging them by position
    /// turned one icon into two, at both its old and its new place. One
    /// window is a consistent picture of the bar; several are not.
    /// - Returns: the index of that window, or nil when none listed anything.
    ///   An index rather than the slots themselves, because the « the caller
    ///   read from the same window has to come with them.
    public static func pickIndex(_ windows: [[HostedSlotReading]], naming pid: pid_t) -> Int? {
        if let named = windows.firstIndex(where: { identified($0, for: pid) }) { return named }
        return windows.firstIndex { !$0.isEmpty }
    }

    /// Whether every slot belonging to `pid` has been named yet — the point
    /// at which reading further windows can tell the caller nothing new.
    ///
    /// False when `pid` has no slot at all: a window that lists none of our
    /// items says nothing about whether we are on the bar, and the next one
    /// may list them.
    public static func identified(_ slots: [HostedSlotReading], for pid: pid_t) -> Bool {
        let ours = slots.filter { $0.pid == pid }
        return !ours.isEmpty && ours.allSatisfy { $0.identifier != nil }
    }
}
