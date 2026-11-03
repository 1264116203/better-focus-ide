# AGENTS.md — BetterFocusIDE

## Project Overview

BetterFocusIDE is a macOS 14+ accessory app (LSUIElement, no Dock icon) that turns the MacBook notch into a "Dynamic Island" notification assistant for AI coding agents. It receives events from **Qoder** (Python hook) and **OpenCode** (JavaScript plugin) over a Unix Domain Socket, displays interactive cards (questions, permission requests, turn-complete notices) in the notch area, and dispatches user answers back to the originating agent.

- **License**: GPL-3.0-or-later
- **Origin**: Swift migration of the Python project `dynamic-Island-python-validate` (Vorssaint reference for animation/UI)
- **Requirements**: macOS 14+, Apple Silicon (`arm64`)
- **Tech stack**: Swift 5.9, SwiftPM executable, AppKit window shell + SwiftUI content

## Build & Run

```bash
# Compile (debug)
swift build -c debug

# Full build: compile + assemble .app bundle + ad-hoc sign
./build.sh
# → .build/debug/BetterFocusIDE.app

# Run
open .build/debug/BetterFocusIDE.app

# Install to /Applications
cp -R .build/debug/BetterFocusIDE.app /Applications/
xattr -dr com.apple.quarantine /Applications/BetterFocusIDE.app  # bypass Gatekeeper
```

**No Xcode project** — this is a pure SwiftPM executable target. Do not generate `.xcodeproj` or `.xcworkspace`.

## Directory Structure

```
├── Package.swift                          # SPM manifest (single executable target)
├── build.sh                               # Build + .app assembly + ad-hoc signing
├── Resources/
│   ├── Info.plist                         # Bundle metadata (LSUIElement=true, zh-Hans)
│   └── BetterFocusIDE.entitlements        # Sandbox: apple-events + process querying
├── Sources/BetterFocusIDE/
│   ├── App/
│   │   ├── main.swift                     # Entry point: Log.setup() → NSApplication.run()
│   │   └── AppDelegate.swift              # Lifecycle, status bar menu, single-instance guard
│   ├── Models/                            # Pure data types (no business logic)
│   │   ├── AgentProvider.swift            # Qoder vs OpenCode identity + tint colors
│   │   ├── AgentQuestion.swift            # Question card model (multi-select, options)
│   │   ├── AgentSocketMessage.swift       # Wire protocol: JSON over Unix socket
│   │   ├── HistoryEntry.swift             # Notification history record
│   │   ├── PermissionRequest.swift        # Permission card model (allow/always/deny)
│   │   └── TurnNotice.swift               # Turn-complete notice + transcript parsing
│   ├── Services/
│   │   ├── Socket/
│   │   │   └── AgentEventSocketServer.swift   # Unix socket listener (DispatchSourceRead)
│   │   ├── Installer/
│   │   │   ├── HelperTemplate.swift           # Embedded Python hook template
│   │   │   ├── InstallerPaths.swift           # File paths for hook/plugin installation
│   │   │   ├── OpenCodePluginInstaller.swift  # JS plugin install/uninstall
│   │   │   └── QoderHookInstaller.swift       # Python hook install/uninstall
│   │   ├── NotchService.swift             # ★ Central orchestrator (~960 lines)
│   │   ├── NotchSupport.swift              # Layout constants + geometry + spring physics
│   │   ├── NotchWindowHost.swift           # AppKit view hosting SwiftUI content
│   │   ├── Settings.swift                  # Persistent config (UserDefaults + JSON file)
│   │   ├── SettingCatalog.swift            # Declarative settings schema definition
│   │   ├── AnswerDispatcher.swift          # Write answers back to agent files
│   │   ├── QuestionController.swift        # Question card state machine
│   │   ├── PermissionController.swift      # Permission card state machine
│   │   ├── NoticeController.swift          # Notice banner + bell swing animation
│   │   ├── HistoryController.swift         # Recent 5 notifications
│   │   ├── Keymap.swift                    # Keyboard shortcut definitions
│   │   ├── Logging.swift                   # Structured logger (file + stderr, 5MB×3 rotation)
│   │   ├── Doctor.swift                    # Self-diagnostic checks
│   │   ├── FeedbackService.swift           # Haptic + audio feedback
│   │   ├── IDELauncher.swift               # Activate/focus IDE windows via AppleEvents
│   │   └── Transcript.swift                # Read session titles from .jsonl files
│   └── UI/                                # SwiftUI views (dark mode enforced)
│       ├── NotchView.swift                 # Main container: collapsed/expanded routing
│       ├── NotchAgentQuestionView.swift    # Question card UI
│       ├── NotchPermissionView.swift       # Permission card UI
│       ├── NotchNoticeView.swift           # Notice banner UI
│       ├── NotchHistoryView.swift          # History panel UI
│       ├── SettingsView.swift              # Settings panel (resizable window)
│       └── DoctorView.swift                # Doctor diagnostic UI
└── graphify-out/                           # Knowledge graph outputs (auto-generated)
```

## Architecture

### Four-Layer Notch Stack

The notch follows a strict layering inherited from the Python reference:

1. **Window Shell** — `NotchPanel` (NSPanel subclass): borderless, transparent, `level = statusBar + 1`, specific `collectionBehavior`. Must call `orderFrontRegardless()` to become visible (not just `setFrame`).
2. **Animation Layer** — `NotchCanvas` (NSView): hosts `CALayer` shape keyframe animations (`CAKeyframeAnimation` driving mask paths for the liquid island silhouette).
3. **Bridge Layer** — `NotchHostingView` (NSHostingView<AnyView> subclass): bridges AppKit ↔ SwiftUI.
4. **Content Layer** — `NotchView` (SwiftUI): all card UI, state driven by `ObservableObject` `NotchService`.

**Key constraint**: The toggle, custom hit-test, and frame-by-frame spring animation cannot be done in pure SwiftUI. AppKit thin shell + SwiftUI content is mandatory.

### Card State Machine

Four card types, each with a dedicated controller:

| Card Type | Controller | Trigger Event | Answer Mechanism |
|-----------|-----------|---------------|-----------------|
| Question | `QuestionController` | `question_requested` | Write JSON to `answers/<session>_<question>.json` |
| Permission | `PermissionController` | `permission_requested` | Write JSON to `answers/<session>_<request>.json` |
| Notice | `NoticeController` | `turn_finished` / `session_ended` | Auto-dismiss after `notifyBannerDuration` |
| History | `HistoryController` | Internal | Read-only panel (recent 5 entries) |

Cards support **pin mode** (stay expanded) vs **auto-dismiss** (retract after timeout). A 0.5s click guard prevents accidental keyboard input during card transitions.

### Inter-Process Communication

```
Qoder Hook (Python) ──┐
                      ├── Unix Socket ──→ AgentEventSocketServer ──→ NotchService
OpenCode Plugin (JS) ─┘                          │                    │
                      ←── Answer Files ←── AnswerDispatcher ←────────┘
```

- **Inbound**: Newline-delimited JSON over `~/Library/Application Support/BetterFocusIDE/agent-events.sock`
- **Outbound**: Answer files written to `~/Library/Application Support/BetterFocusIDE/answers/`
- **Protocol**: See `AgentSocketMessage` and `SocketEvent` for the wire format

### Single-Instance Lock

The Unix socket file itself is the lock anchor:
1. `AgentEventSocketServer.start()` attempts `flock(LOCK_EX|LOCK_NB)` on `<socket>.lock`
2. A `connect()` probe checks if another instance is already listening
3. Returns `StartOutcome`: `.started`, `.alreadyRunning`, `.failed`
4. Duplicate launches must `NSApp.terminate(nil)` silently — **never** use `NSAlert().runModal()` (blocks main thread → zombie process)

### Settings System

- **Storage**: `~/Library/Application Support/BetterFocusIDE/settings.json`
- **Live propagation**: `Settings.changes` (PassthroughSubject) → `NotchService.handleSettingsChanged()` → re-layout without animation
- **Schema**: `SettingCatalog` defines all settings declaratively with `SettingDefinition` (key, kind, group, get/set closures)
- **Color encoding**: RGB stored as `"r,g,b"` strings via `AnyCodableValue` (only supports string/int/double/bool)
- **Backward compatibility**: `Settings.load()` uses `??` fallback for missing keys, so new fields work with old JSON

**Critical invariant**: `handleSettingsChanged()` must NEVER write back to any Settings field — that creates a feedback loop.

### Installer System

`QoderHookInstaller` and `OpenCodePluginInstaller` are **idempotent**: they write files tagged with `betterfocus` markers and skip if content is unchanged. Settings with `needsReinstall: true` (e.g., `agentWaitLimit`) trigger re-installation, but the installers must actually read the current setting value or the write-back is a no-op.

## Coding Conventions

### Language & Style

- **Swift 5.9** with strict `set -euo pipefail` in shell scripts
- All source files carry the SPDX header: `// SPDX-License-Identifier: GPL-3.0-or-later`
- Chinese is used for user-facing strings (labels, menu items, settings groups)
- Code comments are in English; commit messages in English
- Follow existing naming: `Notch*` for window/geometry, `*Controller` for card state, `*View` for SwiftUI

### UI Patterns

- All UI is SwiftUI with dark mode enforced
- `ObservableObject` for reactive state (NotchService, Settings)
- `@Published` properties for automatic view updates
- `PassthroughSubject` for one-shot event broadcasting
- Settings panel uses `SettingCatalog` declarative schema — do not hardcode UI rows

### Animation

- Spring physics in `NotchMotion.Spring` — aligned with Python `motion.spring_for`
- `CAKeyframeAnimation` drives the mask path for the liquid island silhouette
- `reduce_motion` is tri-state: `"system"` / `"on"` / `"off"` — when resolved to true, bounce is forced to 0 but animation still runs (monotonic, no overshoot)
- Frame rate: `animationFps = 0` means auto (120Hz ProMotion)

### Error Handling

- Use `try?` for non-critical operations (file I/O, JSON parsing)
- Log errors via `Log.error()` with topic tags
- Never crash on malformed socket messages — drop silently

## Key Invariants

These MUST be preserved across all changes:

1. **Window visibility**: `present()` only sets frame; must call `panel.orderFrontRegardless()` to actually show
2. **No modal alerts on duplicate launch**: accessory app re-entry must be silent (`NSLog` + `terminate`)
3. **Settings feedback loop**: `handleSettingsChanged()` is read-only w.r.t. Settings
4. **Socket lock**: `bindAndListen()` must NOT unconditionally delete the socket file (would steal from running instance)
5. **Transcript titles**: `turn_finished` payload carries `transcript_path` only (no `session_title`); the island reads the .jsonl itself via `Transcript.sessionSummary()`
6. **Click guard**: Cards ignore input for `clickGuard` seconds after appearance, during "other…" text entry, during fade-out, and when collapsed into the bubble
7. **Notch screen pinning**: Always target the display with `safeAreaInsets.top > 0`, never `NSScreen.main`
8. **Mask alignment**: `Shape.path(in:)` ignores `rect.origin` — the mask must be offset-aware or it drifts from the centered host

## Data Files

All under `~/Library/Application Support/BetterFocusIDE/`:

| File | Purpose |
|------|---------|
| `agent-events.sock` | Unix socket for agent events |
| `agent-events.sock.lock` | flock-based single-instance lock |
| `settings.json` | User preferences (versioned, backward-compatible) |
| `answers/*.json` | Answer files read by hooks/plugins |
| `logs/betterfocus.log` | Rotating log (5MB × 3, sanitized) |

Hook/plugin files installed externally:

| File | Purpose |
|------|---------|
| `~/.qoder/hooks/betterfocus-notify.sh` | Qoder hook launcher |
| `~/.qoder/hooks/betterfocus-hook.py` | Qoder hook body |
| `~/.qoder/settings.json` | Qoder hook registration (with `betterfocus` marker) |
| `~/.config/opencode/plugins/betterfocus-notify.js` | OpenCode plugin |

## Common Tasks

### Adding a New Setting

1. Add `@Published` property to `Settings.swift` with default value
2. Add read/write in `Settings.load()` and `Settings.save()` (use `??` for backward compat)
3. Add to `Settings.resetAll()`
4. Add `SettingDefinition` to `SettingCatalog.all` with appropriate `kind`, `group`, `section`
5. If it needs to trigger hook re-install, set `needsReinstall: true` and update `InstallerPaths`

### Adding a New Card Type

1. Create model in `Models/`
2. Create controller in `Services/` (follow `QuestionController` pattern)
3. Add case to `ActiveCard` enum in `NotchService`
4. Create SwiftUI view in `UI/`
5. Wire into `NotchView` routing
6. Add keyboard handling in `Keymap` if needed

### Modifying Animation

1. Spring parameters live in `NotchMotion` — do not hardcode in views
2. Always check `Settings.shared.reduceMotionResolved` before applying bounce
3. `NotchLayout` constants are read at call time from `Settings.shared` for live updates

### Debugging

```bash
# Enable stderr logging
BETTERFOCUS_LOG_STDERR=1 open .build/debug/BetterFocusIDE.app

# Set log level
BETTERFOCUS_LOG_LEVEL=debug BETTERFOCUS_LOG_STDERR=1 .build/debug/BetterFocusIDE

# Check socket
ls -la ~/Library/Application\ Support/BetterFocusIDE/agent-events.sock

# Run doctor
# Status bar → 自检 (Doctor)…
```

## Testing

There is no automated test suite. Manual testing workflow:

1. Build: `./build.sh`
2. Launch: `open .build/debug/BetterFocusIDE.app`
3. Trigger events: use Qoder/OpenCode with the hook installed, or send JSON directly to the socket
4. Verify: card appearance, keyboard shortcuts, pin/unpin, history, settings changes, doctor checks
5. Check logs: `~/Library/Application Support/BetterFocusIDE/logs/betterfocus.log`
