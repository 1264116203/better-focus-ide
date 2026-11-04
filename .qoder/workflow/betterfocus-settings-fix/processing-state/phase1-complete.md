# Phase 1: 根因诊断完成

## 状态
PASS

## 产出物
- `01-rootcause.md`: 根因分析文档

## Metrics
- phase_started_at: 2026-11-04T10:29:59
- phase_completed_at: 2026-11-04T10:35:00
- duration: 0h 5m 1s

## OUTPUTS
- .qoder/workflow/betterfocus-settings-fix/01-rootcause.md

## 根因摘要
SwiftUI 视图直接读取 `Settings.shared` 的属性，但未将其声明为 `@ObservedObject`，导致设置变更时视图不会重新渲染。

## 需要修复的文件
1. `Sources/BetterFocusIDE/UI/NotchAgentQuestionView.swift` - 读取 bodyFont/optionFont/descFont/cardInset
2. `Sources/BetterFocusIDE/UI/NotchPermissionView.swift` - 读取 cardInset
