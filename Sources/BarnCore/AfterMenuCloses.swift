// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Run `work` once the main run loop is back in its default mode, i.e. after
/// any menu that is open has finished closing.
///
/// A menu item's action is sent while the menu's tracking loop is still
/// running. An alert shown from there (2026-09-29: "No room to show
/// SoundChain") interrupts the menu's fade-out; after OK the menu is left
/// open at almost zero alpha, still tracking, and every click goes to it.
/// Scheduling for the default mode only means the menu's own loop has ended.
public func afterMenuCloses(_ work: @escaping () -> Void) {
    RunLoop.main.perform(inModes: [.default], block: work)
}
