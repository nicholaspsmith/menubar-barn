// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// One peek.
///
/// The session carries its own deadline so that *both* ends can decide to
/// restore without further messages. That is the point: every app that yields
/// its status item arms a local timer from this TTL, so if Barn crashes or is
/// force-quit mid-peek, the icons come back on their own. No shutdown path can
/// leave the user's menu bar broken.
public struct YieldSession: Equatable, Sendable {
    public let token: String
    public let ttl: TimeInterval
    public let startedAt: TimeInterval

    public init(token: String, ttl: TimeInterval, startedAt: TimeInterval) {
        self.token = token
        self.ttl = ttl
        self.startedAt = startedAt
    }

    public func isExpired(at now: TimeInterval) -> Bool { now >= startedAt + ttl }

    /// Restarts the clock from `now`, keeping the token — used when the user
    /// clicks inside the revealed block, so that reading a menu does not get cut
    /// off mid-way.
    public func extended(at now: TimeInterval, by ttl: TimeInterval) -> YieldSession {
        YieldSession(token: token, ttl: ttl, startedAt: now)
    }
}
