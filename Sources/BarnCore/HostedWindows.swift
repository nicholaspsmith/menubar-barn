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
/// Barn reads the windows in turn and merges what they say.
public enum HostedWindows {
    /// One slot per position, with the identifier from whichever window
    /// carried one. Frames and order come from the first window that listed
    /// the slot; a window that lists a slot the others missed still
    /// contributes it.
    public static func merge(_ windows: [[HostedSlotReading]]) -> [HostedSlotReading] {
        /// A slot is its owner and where it sits: two items never share both.
        struct Key: Hashable {
            let pid: pid_t
            let minX: Int
            let width: Int

            init(_ reading: HostedSlotReading) {
                pid = reading.pid
                minX = Int(reading.frame.minX.rounded())
                width = Int(reading.frame.width.rounded())
            }
        }

        var order: [Key] = []
        var merged: [Key: HostedSlotReading] = [:]
        for window in windows {
            for reading in window {
                let key = Key(reading)
                guard let existing = merged[key] else {
                    order.append(key)
                    merged[key] = reading
                    continue
                }
                if existing.identifier == nil, reading.identifier != nil {
                    merged[key] = HostedSlotReading(
                        pid: existing.pid,
                        frame: existing.frame,
                        identifier: reading.identifier
                    )
                }
            }
        }
        return order.compactMap { merged[$0] }
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
