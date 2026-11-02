// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import AppKit

Log.setup()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
