#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Report what the menu bar looks like and flag anything stranded.
# Needs Accessibility for whichever terminal runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift scripts/verify-menubar.swift
