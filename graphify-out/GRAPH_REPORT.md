# Graph Report - better-focus-ide  (2026-11-03)

## Corpus Check
- Corpus is ~30,485 words - fits in a single context window. You may not need a graph.

## Summary
- 829 nodes · 1810 edges · 30 communities (25 shown, 5 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 99 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Notch Service & Cards
- Agent Question Model
- Animation & Visual Effects
- Agent Provider Config
- Turn Notice Model
- Notch Geometry Layout
- Settings Catalog Definition
- Settings Persistence
- App Entry & Core
- Keyboard Input Handling
- Hook Plugin Installer
- Transcript Session
- History Entry Model
- Core Service Components
- Socket Message Codable
- Socket Server Binding
- Doctor Self-Check
- Logging Service
- App Delegate Menu
- Answer Dispatcher
- Socket Event Types
- App Launch Logging
- Socket Message Keys
- Socket Message Decoding
- Socket Start Outcome
- App Termination
- Build Script
- AnyCodable Decoder
- AnyCodable Encoder
- Package Definition

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
- `.pendingTint` --calls--> `AgentProvider`  [INFERRED]
  Sources/BetterFocusIDE/Services/NoticeController.swift → Sources/BetterFocusIDE/Models/AgentProvider.swift
- `.tint` --calls--> `AgentProvider`  [INFERRED]
  Sources/BetterFocusIDE/UI/NotchNoticeView.swift → Sources/BetterFocusIDE/Models/AgentProvider.swift
- `NotchService` --calls--> `HistoryController`  [INFERRED]
  Sources/BetterFocusIDE/Services/NotchService.swift → Sources/BetterFocusIDE/Services/HistoryController.swift
- `NotchService` --calls--> `NoticeController`  [INFERRED]
  Sources/BetterFocusIDE/Services/NotchService.swift → Sources/BetterFocusIDE/Services/NoticeController.swift
- `NotchService` --calls--> `PermissionController`  [INFERRED]
  Sources/BetterFocusIDE/Services/NotchService.swift → Sources/BetterFocusIDE/Services/PermissionController.swift

## Import Cycles
- None detected.

## Communities (30 total, 5 thin omitted)

### Community 0 - "Notch Service & Cards"
Cohesion: 0.06
Nodes (30): NSObjectProtocol, NSScreen, ActiveCard, history, none, notice, permission, question (+22 more)

### Community 1 - "Agent Question Model"
Cohesion: 0.06
Nodes (42): Equatable, AgentQuestion, AgentQuestionAnswer, .answerIndex, .answerIndices, custom, option, options (+34 more)

### Community 2 - "Animation & Visual Effects"
Cohesion: 0.08
Nodes (33): AnyView, CAAnimation, CAAnimationDelegate, CAKeyframeAnimation, CALayer, CFTimeInterval, Float, NSAccessibility (+25 more)

### Community 3 - "Agent Provider Config"
Cohesion: 0.06
Nodes (42): CaseIterable, AgentProvider, .displayName, opencode, qoder, .tint, .tintRGB, Color (+34 more)

### Community 4 - "Turn Notice Model"
Cohesion: 0.06
Nodes (32): NSSound, Bool, Date, String, TurnNotice, FeedbackService, Bool, String (+24 more)

### Community 5 - "Notch Geometry Layout"
Cohesion: 0.07
Nodes (41): CoreGraphics, Path, Shape, NotchGeometry, .collapsed, .floats, .safeContentTop, .stripHeight (+33 more)

### Community 6 - "Settings Catalog Definition"
Cohesion: 0.09
Nodes (42): KeyPath, ReferenceWritableKeyPath, getB(), getD(), getI(), getIS(), getRGB(), getS() (+34 more)

### Community 7 - "Settings Persistence"
Cohesion: 0.10
Nodes (25): Identifiable, SettingCatalog, SettingDefinition, .id, Metric, PageItem, .id, row (+17 more)

### Community 8 - "App Entry & Core"
Cohesion: 0.06
Nodes (21): AppKit, Combine, Foundation, InstallerPaths, .answerDir, .appSupport, .hookTimeoutSeconds, .opencodePluginPath (+13 more)

### Community 9 - "Keyboard Input Handling"
Cohesion: 0.09
Nodes (26): NSViewRepresentable, NSVisualEffectView, OptionSet, Action, collapse, decide, nav, option (+18 more)

### Community 10 - "Hook Plugin Installer"
Cohesion: 0.12
Nodes (15): HelperTemplate, OpenCodePluginInstaller, .isInstalled, .pluginContent, PluginTemplate, Bool, String, QoderHookInstaller (+7 more)

### Community 11 - "Transcript Session"
Cohesion: 0.20
Nodes (10): FileHandle, NSRegularExpression, Session, .fromCLI, Any, Bool, Data, Int (+2 more)

### Community 12 - "History Entry Model"
Cohesion: 0.11
Nodes (17): ObservableObject, HistoryEntry, .badgeText, .clockText, Date, DateFormatter, Double, String (+9 more)

### Community 13 - "Core Service Components"
Cohesion: 0.10
Nodes (26): AgentEventSocketServer, Doctor自检, 通知历史, Hook/Plugin Installer, 键盘答卡, 落盘日志, 回复完成通知, 权限卡片 (+18 more)

### Community 14 - "Socket Message Codable"
Cohesion: 0.11
Nodes (20): Codable, AnyCodableValue, array, .arrayValue, bool, .boolValue, dictionary, .dictValue (+12 more)

### Community 15 - "Socket Server Binding"
Cohesion: 0.16
Nodes (8): DispatchSourceRead, Error, Int32, AgentEventSocketServer, SocketInUse, Bool, URL, Void

### Community 16 - "Doctor Self-Check"
Cohesion: 0.28
Nodes (7): Doctor, DoctorCheck, Bool, Int, String, DoctorView, .body

### Community 17 - "Logging Service"
Cohesion: 0.18
Nodes (10): Comparable, Int, Log, LogLevel, debug, error, info, .label (+2 more)

### Community 18 - "App Delegate Menu"
Cohesion: 0.20
Nodes (8): Content, NSApplicationDelegate, NSObject, NSStatusItem, AppDelegate, CGSize, NSWindow, String

### Community 19 - "Answer Dispatcher"
Cohesion: 0.33
Nodes (6): AnswerDispatcher, Any, Int, String, TimeInterval, URL

### Community 20 - "Socket Event Types"
Cohesion: 0.15
Nodes (10): SocketEvent, activity, permissionRequested, permissionResolved, permissionTimeout, questionAnswered, questionRequested, questionTimeout (+2 more)

### Community 21 - "App Launch Logging"
Cohesion: 0.27
Nodes (3): NSMenu, String, Data

### Community 22 - "Socket Message Keys"
Cohesion: 0.25
Nodes (8): CodingKey, CodingKeys, event, host, payload, provider, sessionID, timestamp

### Community 23 - "Socket Message Decoding"
Cohesion: 0.53
Nodes (4): JSONDecoder, AgentSocketMessage, Date, String

### Community 24 - "Socket Start Outcome"
Cohesion: 0.40
Nodes (5): StartOutcome, alreadyRunning, failed, started, String

## Knowledge Gaps
- **164 isolated node(s):** `PackageDescription`, `qoder`, `opencode`, `.displayName`, `.tint` (+159 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 280 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `NotchService` connect `Notch Service & Cards` to `Agent Question Model`, `Animation & Visual Effects`, `Agent Provider Config`, `Turn Notice Model`, `Notch Geometry Layout`, `App Entry & Core`, `Keyboard Input Handling`, `Hook Plugin Installer`, `History Entry Model`, `App Delegate Menu`, `Socket Event Types`, `App Termination`?**
  _High betweenness centrality (0.287) - this node is a cross-community bridge._
- **Why does `Foundation` connect `App Entry & Core` to `Agent Question Model`, `Agent Provider Config`, `Turn Notice Model`, `Settings Catalog Definition`, `Hook Plugin Installer`, `Transcript Session`, `History Entry Model`, `Socket Server Binding`, `Doctor Self-Check`, `Logging Service`, `Socket Event Types`?**
  _High betweenness centrality (0.146) - this node is a cross-community bridge._
- **Why does `NotchGeometry` connect `Notch Geometry Layout` to `Notch Service & Cards`, `Agent Question Model`, `Animation & Visual Effects`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Are the 5 inferred relationships involving `NotchService` (e.g. with `HistoryController` and `NoticeController`) actually correct?**
  _`NotchService` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `NotchCanvas` (e.g. with `NSVisualEffectView` and `.animateTo()`) actually correct?**
  _`NotchCanvas` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `QuestionController` (e.g. with `NotchService` and `.questionCardHeight()`) actually correct?**
  _`QuestionController` has 5 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `qoder`, `opencode` to the rest of the system?**
  _164 weakly-connected nodes found - possible documentation gaps or missing edges._