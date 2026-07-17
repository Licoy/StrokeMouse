# AGENTS.md — StrokeMouse

给人类协作者与 AI Agent 的工程说明。修改代码前请先阅读本文件与 `README.md`。

## 一句话

**StrokeMouse** 是 macOS 上的鼠标手势自定义应用：监听**每条手势配置的触发键** + 轨迹，匹配配置后执行动作。  
Bundle ID：Release `com.strokemouse.app`；Debug `com.strokemouse.app.dev`（显示名 **StrokeMouse Dev**，与正式版在辅助功能中分开授权）。

## 技术栈

| 项 | 选择 |
|----|------|
| 语言 | Swift 5.10+ |
| UI | SwiftUI（`MenuBarExtra` + `Settings`） |
| 架构 | 轻量 MVVM + Service（`@Observable` / `AppState`） |
| 最低系统 | macOS 14 |
| 事件 | `CGEventTap`（需 Accessibility） |
| 配置 | Codable JSON → `Application Support/StrokeMouse/` |
| i18n | `Localizable.xcstrings`（en + zh-Hans） |
| 工程 | XcodeGen（`project.yml`） |
| 依赖 | LaunchAtLogin-Modern（登录启动）+ Sparkle（应用内更新） |
| 签名 | 开发用 `StrokeMouse Dev`；可不签/ad-hoc 分发 |

**不使用**：TCA、Core Data/GRDB、App Sandbox（当前）。

## 架构分层

```text
SwiftUI Views (Features/*)
        ↓
AppState / View 局部状态
        ↓
Services: GestureEngine, ActionExecutor, ConfigStore, PermissionManager
        ↓
Platform: MouseEventTap, PathSimplifier, TemplateMatcher, AX / CGEvent helpers
```

- **UI 不直接**创建 `CGEventTap` 或写配置文件；经 `AppState` / Service。
- **识别算法**保持纯函数风格（`PathSimplifier` / `DirectionQuantizer` / `TemplateMatcher`），便于单测。
- **动作执行**集中在 `ActionExecutor`，按 `GestureAction` 分发。

## 目录地图

```text
project.yml
scripts/
  generate_project.sh
  build_release.sh
  package-app.sh
bump.sh
StrokeMouse/
  App/
    StrokeMouseApp.swift      # @main, MenuBarExtra, Settings
    AppDelegate.swift
    AppState.swift            # 组合 Config / Engine / Permissions
  Features/
    MenuBar/                  # 菜单栏菜单
    Settings/                 # 手势 / 通用 / 权限 / 关于
    GestureEditor/            # 编辑 profile、录制轨迹、选动作
    Onboarding/               # 首次引导
  Core/
    EventTap/MouseEventTap.swift
    GestureRecognition/       # 简化、方向量化、模板匹配、Engine
    Actions/                  # 快捷键、媒体、窗口、脚本
    Config/                   # Models, Store, Defaults
    Permissions/PermissionManager.swift
    Updates/                    # Sparkle 更新环境、服务与自定义界面
  Resources/
    Localizable.xcstrings
    Assets.xcassets
    Info.plist
  Supporting/
    Constants.swift
    StrokeMouse.entitlements
StrokeMouseTests/
```

## 常用命令

```bash
# 安装 XcodeGen（仅一次）
brew install xcodegen

# 生成 / 刷新 Xcode 工程（改 project.yml 或增删文件后执行）
./scripts/generate_project.sh

# 打开
open StrokeMouse.xcodeproj

# 构建
xcodebuild -scheme StrokeMouse -configuration Debug build

# 测试
xcodebuild -scheme StrokeMouse -configuration Debug test

# 双架构 Release 产物（ad-hoc + Hardened Runtime）
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
# CI：PR 触达 App 路径才跑 test；push main 默认不跑 test/package。
# website：PR 触达 website/** 跑 .github/workflows/website.yml（仅 build）；
# main 上 website/** 变更 / Release / 手动 → deploy-website.yml 部署 GitHub Pages。
# package 手动：Actions → CI → Run workflow，勾选 package。
# Release package：arm64 → macos-26；x86_64 → macos-26-intel（原生 Intel runner）

# 提升版本、提交并创建 tag；加 -p 原子推送；--force 允许同版本重打 tag 并推送
./bump.sh -v 0.0.2
./bump.sh -v 0.0.2 -p
./bump.sh -v 0.0.1 --force
```

**不要**手改 `StrokeMouse.xcodeproj` 作为长期方案；改 `project.yml` 后重新 generate。

## 编码约定

1. **用户可见文案**必须走 `String(localized:)` / String Catalog，同时提供 **en** 与 **zh-Hans**。
2. 新配置字段加入 `ConfigModels` 时保持 `Codable` 向后兼容（缺省值 / 可选字段）。
3. 主线程：UI 与 `@MainActor` Service（`ConfigStore`、`GestureEngine`、`AppState`）；耗时脚本用 `async` 后台。
4. 避免无关大重构；改动聚焦需求。
5. 权限失败要可观测（菜单栏状态文案 / 权限页），不要静默失败。
6. Shell / AppleScript 视为高权限能力，UI 需保留风险提示。

## 权限与安全注意

- `MouseEventTap` 依赖 `AXIsProcessTrusted()`；未授权时不得假装在监听。
- `MouseEventTap` 使用 `.defaultTap`，只捕获已配置触发键且由它收到 down 的 down/up；drag 必须在通知手势引擎后返回原事件，以保持系统游标位置更新。前台 App 不会收到配对的 down/up，因此不得出现或选中右键菜单。未达到 `minStrokeDistance` 的短按必须用带 `.eventSourceUserData` 标记的合成 down/up 回放，标记事件直接放行且不得重入手势引擎。左键、未监控按钮和没有配对 down 的事件始终放行。
- Entitlements：`app-sandbox = false`，`automation.apple-events = true`。
- 勿在日志中打印用户脚本全文到公开渠道。

## 手势识别要点

1. **触发键在 `GestureProfile.trigger` 上**（默认右键）；引擎只监听已启用手势用到的按键集合  
2. 对应按键按下 → 采样路径 → 位移超过 `minStrokeDistance` 才算有效  
3. 松开 → 仅在同按键的候选中匹配：
   - `freePath`：有序弧长重采样 + 1D/2D 归一化 + `±12°` 有限旋转匹配 ≥ `freePathMatchThreshold`
   - 显著段数 / 连续转角作为不可补偿的结构门控；不使用镜像、逆序或 near-miss 兜底
4. 结合 `AppScope` 与前台 `bundleIdentifier` 过滤候选

调参常量见 `Constants.swift`。

## 明确不在一期范围

- 触控板多指完整手势、BTT 级链式编排、云同步、MAS 沙盒上架、插件市场

## 提交与 PR

- Commit 中英文均可，说明「为什么」优于堆砌文件名。
- 改 UI 文案时同步更新 `Localizable.xcstrings`。
- 改算法时补充 / 更新 `StrokeMouseTests`。
- 改 `project.yml` 后确保 `xcodegen generate` 与本地 build 通过。

## 相关文件

- 产品说明与用户向文档：`README.md`
- 工程生成：`project.yml`
- 版本：`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 在 `project.yml`
- 发布：`RELEASING.md`、`.github/workflows/release.yml`
