# Graph Report - better-focus-ide  (2026-11-03)

## Corpus Check
- 42 files · ~29,617 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 864 nodes · 1851 edges · 36 communities (27 shown, 8 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 101 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7aa18968`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- NotchService
- QuestionController
- NotchCanvas
- View
- NoticeController
- NotchGeometry
- Settings
- AGENTS.md — BetterFocusIDE
- InstallerPaths
- Action
- QoderHookInstaller
- Transcript
- HistoryEntry
- BetterFocusIDE
- AnyCodableValue
- AgentEventSocketServer
- DoctorCheck
- Log
- AppDelegate
- AnswerDispatcher
- SocketEvent
- .write
- CodingKeys
- AgentSocketMessage
- StartOutcome
- .applicationWillTerminate
- build.sh
- SwiftUI
- SettingsView
- Package.swift
- Foundation
- NotchHistoryView
- BetterFocusIDE
- .init
- .encode

## God Nodes (most connected - your core abstractions)
1. `NotchService` - 82 edges
2. `SettingsView` - 38 edges
3. `NotchCanvas` - 35 edges
4. `QuestionController` - 35 edges
5. `Settings` - 34 edges
6. `AnyCodableValue` - 32 edges
7. `SettingDefinition` - 28 edges
8. `PermissionRequest` - 26 edges
9. `SettingValue` - 24 edges
10. `NotchAgentQuestionView` - 24 edges

## Surprising Connections (you probably didn't know these)
- `.tint` --calls--> `AgentProvider`  [INFERRED]
  Sources/BetterFocusIDE/UI/NotchNoticeView.swift → Sources/BetterFocusIDE/Models/AgentProvider.swift
- `run()` --calls--> `AppDelegate`  [INFERRED]
  Sources/BetterFocusIDE/Library.swift → Sources/BetterFocusIDE/App/AppDelegate.swift
- `.pendingTint` --calls--> `AgentProvider`  [INFERRED]
  Sources/BetterFocusIDE/Services/NoticeController.swift → Sources/BetterFocusIDE/Models/AgentProvider.swift
- `NotchService` --calls--> `HistoryController`  [INFERRED]
  Sources/BetterFocusIDE/Services/NotchService.swift → Sources/BetterFocusIDE/Services/HistoryController.swift
- `NotchService` --calls--> `NoticeController`  [INFERRED]
  Sources/BetterFocusIDE/Services/NotchService.swift → Sources/BetterFocusIDE/Services/NoticeController.swift

## Import Cycles
- None detected.

## Communities (36 total, 8 thin omitted)

### Community 0 - "NotchService"
Cohesion: 0.06
Nodes (31): NSObjectProtocol, NSScreen, ActiveCard, history, none, notice, permission, question (+23 more)

### Community 1 - "QuestionController"
Cohesion: 0.06
Nodes (43): Equatable, Identifiable, AgentQuestion, AgentQuestionAnswer, .answerIndex, .answerIndices, custom, option (+35 more)

### Community 2 - "NotchCanvas"
Cohesion: 0.08
Nodes (33): AnyView, CAAnimation, CAAnimationDelegate, CAKeyframeAnimation, CALayer, CFTimeInterval, Float, NSAccessibility (+25 more)

### Community 3 - "View"
Cohesion: 0.06
Nodes (45): CaseIterable, ObservableObject, AgentProvider, .displayName, opencode, qoder, .tint, .tintRGB (+37 more)

### Community 4 - "NoticeController"
Cohesion: 0.08
Nodes (27): Bool, Date, String, TurnNotice, HostInfo, .isEmpty, IDELauncher, Bool (+19 more)

### Community 5 - "NotchGeometry"
Cohesion: 0.07
Nodes (41): CoreGraphics, Path, Shape, NotchGeometry, .collapsed, .floats, .safeContentTop, .stripHeight (+33 more)

### Community 6 - "Settings"
Cohesion: 0.09
Nodes (41): KeyPath, ReferenceWritableKeyPath, getB(), getD(), getI(), getIS(), getRGB(), getS() (+33 more)

### Community 7 - "AGENTS.md — BetterFocusIDE"
Cohesion: 0.07
Nodes (26): AGENTS.md — BetterFocusIDE, Graphify 知识图谱（硬性规则）, UI 模式, 修改动画, 关键不变量, 动画, 单实例锁, 卡片状态机 (+18 more)

### Community 8 - "InstallerPaths"
Cohesion: 0.12
Nodes (17): InstallerPaths, .answerDir, .appSupport, .hookTimeoutSeconds, .opencodePluginPath, .opencodePluginsDir, .permissionTimeoutSeconds, .qoderDir (+9 more)

### Community 9 - "Action"
Cohesion: 0.09
Nodes (26): NSViewRepresentable, NSVisualEffectView, OptionSet, Action, collapse, decide, nav, option (+18 more)

### Community 10 - "QoderHookInstaller"
Cohesion: 0.13
Nodes (14): HelperTemplate, OpenCodePluginInstaller, .isInstalled, .pluginContent, PluginTemplate, Bool, String, QoderHookInstaller (+6 more)

### Community 11 - "Transcript"
Cohesion: 0.20
Nodes (10): FileHandle, NSRegularExpression, Session, .fromCLI, Any, Bool, Data, Int (+2 more)

### Community 12 - "HistoryEntry"
Cohesion: 0.16
Nodes (12): PreviewProvider, HistoryEntry, .badgeText, .clockText, Date, DateFormatter, Double, String (+4 more)

### Community 13 - "BetterFocusIDE"
Cohesion: 0.10
Nodes (26): AgentEventSocketServer, Doctor自检, 通知历史, Hook/Plugin Installer, 键盘答卡, 落盘日志, 回复完成通知, 权限卡片 (+18 more)

### Community 14 - "AnyCodableValue"
Cohesion: 0.11
Nodes (20): Codable, AnyCodableValue, array, .arrayValue, bool, .boolValue, dictionary, .dictValue (+12 more)

### Community 15 - "AgentEventSocketServer"
Cohesion: 0.16
Nodes (8): DispatchSourceRead, Error, Int32, AgentEventSocketServer, SocketInUse, Bool, URL, Void

### Community 16 - "DoctorCheck"
Cohesion: 0.25
Nodes (7): Doctor, DoctorCheck, Bool, Int, String, DoctorView, .body

### Community 17 - "Log"
Cohesion: 0.16
Nodes (11): Comparable, Int, run(), Log, LogLevel, debug, error, info (+3 more)

### Community 18 - "AppDelegate"
Cohesion: 0.20
Nodes (8): Content, NSApplicationDelegate, NSObject, NSStatusItem, AppDelegate, CGSize, NSWindow, String

### Community 19 - "AnswerDispatcher"
Cohesion: 0.33
Nodes (6): AnswerDispatcher, Any, Int, String, TimeInterval, URL

### Community 20 - "SocketEvent"
Cohesion: 0.15
Nodes (10): SocketEvent, activity, permissionRequested, permissionResolved, permissionTimeout, questionAnswered, questionRequested, questionTimeout (+2 more)

### Community 21 - ".write"
Cohesion: 0.27
Nodes (3): NSMenu, String, Data

### Community 22 - "CodingKeys"
Cohesion: 0.25
Nodes (8): CodingKey, CodingKeys, event, host, payload, provider, sessionID, timestamp

### Community 23 - "AgentSocketMessage"
Cohesion: 0.53
Nodes (4): JSONDecoder, AgentSocketMessage, Date, String

### Community 24 - "StartOutcome"
Cohesion: 0.40
Nodes (5): StartOutcome, alreadyRunning, failed, started, String

### Community 28 - "SettingsView"
Cohesion: 0.08
Nodes (28): NSSound, FeedbackService, Bool, String, SettingCatalog, SettingDefinition, .id, Bool (+20 more)

### Community 32 - "NotchHistoryView"
Cohesion: 0.28
Nodes (7): NotchHistoryView, .body, .emptyRow, .header, CGFloat, String, Void

## Knowledge Gaps
- **187 isolated node(s):** `PackageDescription`, `BetterFocusIDE`, `qoder`, `opencode`, `.displayName` (+182 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 306 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `NotchService` connect `NotchService` to `QuestionController`, `NotchCanvas`, `View`, `NoticeController`, `NotchGeometry`, `Action`, `QoderHookInstaller`, `HistoryEntry`, `AppDelegate`, `SocketEvent`, `.applicationWillTerminate`, `SwiftUI`?**
  _High betweenness centrality (0.268) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `QuestionController`, `View`, `NoticeController`, `Settings`, `QoderHookInstaller`, `Transcript`, `HistoryEntry`, `AgentEventSocketServer`, `DoctorCheck`, `Log`, `SocketEvent`?**
  _High betweenness centrality (0.135) - this node is a cross-community bridge._
- **Why does `NotchGeometry` connect `NotchGeometry` to `NotchService`, `QuestionController`, `NotchCanvas`?**
  _High betweenness centrality (0.091) - this node is a cross-community bridge._
- **Are the 5 inferred relationships involving `NotchService` (e.g. with `HistoryController` and `NoticeController`) actually correct?**
  _`NotchService` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `NotchCanvas` (e.g. with `NSVisualEffectView` and `.animateTo()`) actually correct?**
  _`NotchCanvas` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `QuestionController` (e.g. with `NotchService` and `.questionCardHeight()`) actually correct?**
  _`QuestionController` has 5 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `BetterFocusIDE`, `qoder` to the rest of the system?**
  _187 weakly-connected nodes found - possible documentation gaps or missing edges._