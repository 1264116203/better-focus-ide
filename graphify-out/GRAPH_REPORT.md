# Graph Report - better-focus-ide  (2026-11-03)

## Corpus Check
- 42 files · ~29,883 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 876 nodes · 1890 edges · 28 communities (22 shown, 5 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 103 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `20d74007`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- NotchService
- QuestionController
- NotchCanvas
- PermissionRequest
- NoticeController
- NotchGeometry
- Settings
- AGENTS.md — BetterFocusIDE
- Foundation
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
- .playSound
- .write
- .applicationWillTerminate
- build.sh
- SettingsView
- Package.swift
- BetterFocusIDE

## God Nodes (most connected - your core abstractions)
1. `NotchService` - 82 edges
2. `SettingsView` - 39 edges
3. `QuestionController` - 36 edges
4. `NotchCanvas` - 35 edges
5. `Settings` - 34 edges
6. `AnyCodableValue` - 32 edges
7. `SettingDefinition` - 28 edges
8. `PermissionRequest` - 27 edges
9. `NotchAgentQuestionView` - 25 edges
10. `AgentQuestionPrompt` - 24 edges

## Surprising Connections (you probably didn't know these)
- `.tint` --calls--> `AgentProvider`  [INFERRED]
  Sources/BetterFocusIDE/UI/NotchNoticeView.swift → Sources/BetterFocusIDE/Models/AgentProvider.swift
- `run()` --calls--> `AppDelegate`  [INFERRED]
  Sources/BetterFocusIDE/Library.swift → Sources/BetterFocusIDE/AppDelegate.swift
- `.pendingTint` --calls--> `AgentProvider`  [INFERRED]
  Sources/BetterFocusIDE/Services/NoticeController.swift → Sources/BetterFocusIDE/Models/AgentProvider.swift
- `NotchService` --calls--> `HistoryController`  [INFERRED]
  Sources/BetterFocusIDE/Services/NotchService.swift → Sources/BetterFocusIDE/Services/HistoryController.swift
- `NotchService` --calls--> `NoticeController`  [INFERRED]
  Sources/BetterFocusIDE/Services/NotchService.swift → Sources/BetterFocusIDE/Services/NoticeController.swift

## Import Cycles
- None detected.

## Communities (28 total, 5 thin omitted)

### Community 0 - "NotchService"
Cohesion: 0.06
Nodes (31): NSObjectProtocol, NSScreen, ActiveCard, history, none, notice, permission, question (+23 more)

### Community 1 - "QuestionController"
Cohesion: 0.06
Nodes (44): Equatable, Identifiable, AgentQuestion, AgentQuestionAnswer, .answerIndex, .answerIndices, custom, option (+36 more)

### Community 2 - "NotchCanvas"
Cohesion: 0.08
Nodes (33): AnyView, CAAnimation, CAAnimationDelegate, CAKeyframeAnimation, CALayer, CFTimeInterval, Float, NSAccessibility (+25 more)

### Community 3 - "PermissionRequest"
Cohesion: 0.05
Nodes (45): CaseIterable, AgentProvider, .displayName, opencode, qoder, .tint, .tintRGB, Color (+37 more)

### Community 4 - "NoticeController"
Cohesion: 0.08
Nodes (30): ObservableObject, Bool, Date, String, TurnNotice, HostInfo, .isEmpty, IDELauncher (+22 more)

### Community 5 - "NotchGeometry"
Cohesion: 0.07
Nodes (41): CoreGraphics, Path, Shape, NotchGeometry, .collapsed, .floats, .safeContentTop, .stripHeight (+33 more)

### Community 6 - "Settings"
Cohesion: 0.09
Nodes (42): KeyPath, ReferenceWritableKeyPath, getB(), getD(), getI(), getIS(), getRGB(), getS() (+34 more)

### Community 7 - "AGENTS.md — BetterFocusIDE"
Cohesion: 0.07
Nodes (26): AGENTS.md — BetterFocusIDE, Graphify 知识图谱（硬性规则）, UI 模式, 修改动画, 关键不变量, 动画, 单实例锁, 卡片状态机 (+18 more)

### Community 8 - "Foundation"
Cohesion: 0.07
Nodes (21): AppKit, Combine, Foundation, InstallerPaths, .answerDir, .appSupport, .hookTimeoutSeconds, .opencodePluginPath (+13 more)

### Community 9 - "Action"
Cohesion: 0.10
Nodes (24): NSVisualEffectView, OptionSet, Action, collapse, decide, nav, option, other (+16 more)

### Community 10 - "QoderHookInstaller"
Cohesion: 0.13
Nodes (14): HelperTemplate, OpenCodePluginInstaller, .isInstalled, .pluginContent, PluginTemplate, Bool, String, QoderHookInstaller (+6 more)

### Community 11 - "Transcript"
Cohesion: 0.20
Nodes (10): FileHandle, NSRegularExpression, Session, .fromCLI, Any, Bool, Data, Int (+2 more)

### Community 12 - "HistoryEntry"
Cohesion: 0.12
Nodes (18): HistoryEntry, .badgeText, .clockText, Date, DateFormatter, Double, String, HistoryController (+10 more)

### Community 13 - "BetterFocusIDE"
Cohesion: 0.10
Nodes (26): AgentEventSocketServer, Doctor自检, 通知历史, Hook/Plugin Installer, 键盘答卡, 落盘日志, 回复完成通知, 权限卡片 (+18 more)

### Community 14 - "AnyCodableValue"
Cohesion: 0.05
Nodes (44): Codable, CodingKey, Decoder, Encoder, JSONDecoder, AgentSocketMessage, AnyCodableValue, array (+36 more)

### Community 15 - "AgentEventSocketServer"
Cohesion: 0.11
Nodes (13): DispatchSourceRead, Error, Int32, AgentEventSocketServer, SocketInUse, StartOutcome, alreadyRunning, failed (+5 more)

### Community 16 - "DoctorCheck"
Cohesion: 0.22
Nodes (9): Doctor, DoctorCheck, Bool, Int, String, DoctorView, .body, DoctorView_Previews (+1 more)

### Community 17 - "Log"
Cohesion: 0.16
Nodes (11): Comparable, Int, run(), Log, LogLevel, debug, error, info (+3 more)

### Community 18 - "AppDelegate"
Cohesion: 0.17
Nodes (9): Content, NSApplicationDelegate, NSObject, NSStatusItem, AppDelegate, CGSize, NSMenu, NSWindow (+1 more)

### Community 19 - "AnswerDispatcher"
Cohesion: 0.33
Nodes (6): AnswerDispatcher, Any, Int, String, TimeInterval, URL

### Community 20 - ".playSound"
Cohesion: 0.39
Nodes (4): NSSound, FeedbackService, Bool, String

### Community 28 - "SettingsView"
Cohesion: 0.08
Nodes (32): NSViewRepresentable, PreviewProvider, SettingCatalog, SettingDefinition, .id, NotchAgentQuestionView_Previews, NotchView_Previews, .previews (+24 more)

## Knowledge Gaps
- **187 isolated node(s):** `PackageDescription`, `BetterFocusIDE`, `qoder`, `opencode`, `.displayName` (+182 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 305 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `NotchService` connect `NotchService` to `QuestionController`, `NotchCanvas`, `PermissionRequest`, `NoticeController`, `NotchGeometry`, `Foundation`, `Action`, `QoderHookInstaller`, `HistoryEntry`, `AgentEventSocketServer`, `AppDelegate`, `.applicationWillTerminate`?**
  _High betweenness centrality (0.266) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Foundation` to `QuestionController`, `PermissionRequest`, `Settings`, `QoderHookInstaller`, `Transcript`, `AnyCodableValue`, `AgentEventSocketServer`, `DoctorCheck`, `Log`?**
  _High betweenness centrality (0.132) - this node is a cross-community bridge._
- **Why does `NotchGeometry` connect `NotchGeometry` to `NotchService`, `QuestionController`, `NotchCanvas`?**
  _High betweenness centrality (0.089) - this node is a cross-community bridge._
- **Are the 5 inferred relationships involving `NotchService` (e.g. with `HistoryController` and `NoticeController`) actually correct?**
  _`NotchService` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `QuestionController` (e.g. with `NotchService` and `.questionCardHeight()`) actually correct?**
  _`QuestionController` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `NotchCanvas` (e.g. with `NSVisualEffectView` and `.animateTo()`) actually correct?**
  _`NotchCanvas` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `BetterFocusIDE`, `qoder` to the rest of the system?**
  _187 weakly-connected nodes found - possible documentation gaps or missing edges._