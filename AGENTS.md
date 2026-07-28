# AGENTS.md — StrokeMouse

给人类协作者与 AI Agent 的工程说明。修改代码前请先阅读本文件与 `README.md`。

## 一句话

**StrokeMouse** 是 macOS 上的鼠标与触控板手势自定义应用：统一处理鼠标绘制、触控板绘制（单修饰键 + 指针轨迹）和实验性触控手势（多指），匹配配置后执行动作。

Bundle ID：Release `com.strokemouse.app`；Debug `com.strokemouse.app.dev`（显示名 **StrokeMouse Dev**，与正式版在辅助功能中分开授权）。

## 技术栈

| 项 | 选择 |
|----|------|
| 语言 | Swift 5.10+ |
| UI | SwiftUI（`MenuBarExtra` + `Settings`） |
| 架构 | 轻量 MVVM + Service（`@Observable` / `AppState`） |
| 最低系统 | macOS 14 |
| 事件 | `CGEventTap` + 动态加载 `MultitouchSupport`（触控手势为实验性能力） |
| 配置 | Codable JSON → `Application Support/StrokeMouse/` |
| i18n | `Localizable.xcstrings`（en + zh-Hans） |
| 工程 | XcodeGen（`project.yml`） |
| 依赖 | LaunchAtLogin-Modern（登录启动）+ Sparkle（应用内更新） |
| 签名 | 开发 `StrokeMouse Dev`；Release **`StrokeMouse Release`** 自签（固定身份，辅助功能跨更新保留）；仅 smoke 可用 ad-hoc |

**不使用**：TCA、Core Data/GRDB、App Sandbox（当前）。

## 架构分层

```text
SwiftUI Views (Features/*)
        ↓
AppState / View 局部状态
        ↓
Services: GestureRuntime, ActionExecutor, ConfigStore, PermissionManager
        ↓
Platform: MouseEventTap, ModifierEventTap, MultitouchSupport bridge,
          PathSimplifier, TemplateMatcher, AX / CGEvent helpers
```

- **UI 不直接**创建 `CGEventTap`、访问私有触控 API 或写配置文件；经 `AppState` / Service。
- **识别算法**保持纯函数风格（`PathSimplifier` / `DirectionQuantizer` / `TemplateMatcher`），便于单测。
- **动作执行**集中在 `ActionExecutor`，按 `GestureAction` 分发。

## 目录地图

```text
project.yml
scripts/
  generate_project.sh
  build_release.sh
  package-app.sh
  generate-codesign-cert.sh   # StrokeMouse Release 自签证书
  import-codesign-p12.sh
  trust-codesign-cert.sh
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
    EventTap/                  # 鼠标 filtering tap + 修饰键 listen-only tap
    GestureRecognition/       # 统一 Runtime、路径匹配、触控分类与会话仲裁
    Trackpad/                  # MultitouchSupport 动态 C bridge + Swift Adapter
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

# 双架构 Release 产物（StrokeMouse Release 自签 + Hardened Runtime）
# 首次：./scripts/generate-codesign-cert.sh --import  并将 certs/*.p12.b64 等写入 CI secrets
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
# 仅本地 smoke：CODE_SIGN_IDENTITY=- SPARKLE_PUBLIC_KEY=... ./scripts/package-app.sh
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
2. **中文 UI 提示断句**：hint / help / caption / empty subtitle / footer / warning 等短提示中，同一条提示内的并列或承接分句使用 **逗号（，）或分号（；）**，不要用 **句号（。）** 把短提示拆成多句。句号仅用于提示真正结束，或长文案中语义独立的段落 / 列表项。英文保持正常句号习惯。  
   - 反例：`为此应用添加手势。在此新建的手势会默认绑定该应用。`  
   - 正例：`为此应用添加手势，在此新建的手势会默认绑定该应用。`
3. **产品对外名称**（UI / 用户文档）：「鼠标绘制」「触控板绘制」「触控手势」。其中「触控板绘制」对应单修饰键 + 指针轨迹；「修饰按键」选择器标签保持不变。工程代码与技术描述仍可用 modifier / multitouch 等术语。
4. 新配置字段加入 `ConfigModels` 时保持 `Codable` 向后兼容（缺省值 / 可选字段）。
5. 主线程：UI 与 `@MainActor` Service（`ConfigStore`、`GestureRuntime`、`AppState`）；耗时脚本用 `async` 后台。
6. 避免无关大重构；改动聚焦需求。
7. 权限失败要可观测（菜单栏状态文案 / 权限页），不要静默失败。
8. Shell / AppleScript 视为高权限能力，UI 需保留风险提示。

## 权限与安全注意

- `MouseEventTap` 依赖 `AXIsProcessTrusted()`；未授权时不得假装在监听。
- `MouseEventTap` 使用 `.defaultTap`，只捕获已配置触发键且由它收到 down 的 down/up。前台 App 不会收到配对的 down/up，因此不得出现或选中右键菜单。未达到 `minStrokeDistance` 的短按必须用带 `.eventSourceUserData` 标记的合成 down/up 回放，标记事件直接放行且不得重入手势引擎。左键、未监控按钮和没有配对 down 的事件始终放行。
- **禁止**把 `mouseMoved` 或任何 `mouseDragged` 放进 filtering tap 的 `eventsOfInterest`：`.defaultTap` 会同步拦截系统光标更新，在 macOS 14 上可导致按住触发键后光标冻结、退出 App 才恢复。所有连续移动事件必须完全绕过 event tap；路径只用 `GestureRuntime` 的 120Hz timer + `NSEvent.mouseLocation` 采样，起点与终点用 down/up 事件自身坐标（Quartz→AppKit 转换）补齐。
- `ModifierEventTap` 必须保持 listen-only，只监听 `flagsChanged`；仅支持 Fn / Control / Option / Shift / Command 中**精确的单个键**，出现额外支持键立即取消。不得吞掉键盘事件，短路径不执行动作，轨迹仍由 120Hz 指针采样获得。
- Event tap 的 CFRunLoop source 跑在**专用线程**（非主线程），避免 UI/主线程卡顿拖死光标投递。
- 触控手势（多指）只允许通过本地 C bridge `dlopen` / `dlsym` 解析 `MultitouchSupport`；禁止静态链接私有框架或引入第三方二进制。私有 callback 必须先复制成稳定值，再送入 Swift 串行队列；stop/unregister 后不得留下悬空 callback。
- 触控手势不拦截 macOS 原生手势，系统动作可能同时发生。不得保存或记录原始触点轨迹；私有后端失败只将 multitouch 通道标为 failed/degraded，不能拖垮 mouse / modifier 通道，也不得模拟回退或静默重试。
- Entitlements：`app-sandbox = false`，`automation.apple-events = true`。
- 勿在日志中打印用户脚本全文到公开渠道。

## 手势识别要点

1. 输入统一保存在 `GestureProfile.input`：`.drawn` 包含鼠标或单修饰键 activation 与 points；`.trackpad` 包含手指数、family 和方向 / 次数
2. 鼠标或修饰键按下 → 采样路径 → 位移超过 `minStrokeDistance` 才算有效；鼠标短按回放点击，修饰键短路径直接结束
3. 绘制结束 → 仅在同 activation 的候选中匹配：
   - `freePath`：有序弧长重采样 + 1D/2D 归一化 + `±12°` 有限旋转匹配 ≥ 当前全局匹配阈值（默认 `freePathMatchThreshold`）
   - 显著段数 / 连续转角作为不可补偿的结构门控；不使用镜像、逆序或 near-miss 兜底
4. 触控手势支持 34 类：三至五指单击 / 双击 / 四向滑动，以及二至五指捏合 / 张开 / 顺逆时针旋转；混合变换、对角滑动和 near-miss 必须拒绝
5. mouse / modifier / multitouch 通过同一 session gate 仲裁；第一个合法 begin 冻结配置 revision、候选 profile、目标应用和精确窗口，其他来源忽略到物理输入归零
6. 使用冻结应用的 `bundleIdentifier` 过滤 `AppScope`；触控手势中应用专属配置优先于全局，同级多个精确匹配视为冲突并执行零个动作；命中动作始终复用冻结目标

调参常量见 `Constants.swift`。

## 触控板支持范围与限制

- 已支持鼠标绘制、触控板绘制（Fn / Control / Option / Shift / Command 单键 + 指针轨迹），以及实验性触控手势总开关；关闭总开关不得删除 profile。
- 34 类触控手势 = 三至五指单击 / 双击（6）+ 三至五指四向滑动（12）+ 二至五指捏合 / 张开（8）+ 二至五指顺逆时针旋转（8）。
- 首版主要验收 Mac 内置触控板；外接 Magic Trackpad 仅 best-effort。
- 不支持两指轻触 / 滑动、修饰键组合、特定手指身份、tipTap / tipSwipe、连续重复动作、用户可调分类阈值或拦截系统手势。
- BTT 级链式编排、云同步、MAS 沙盒上架和插件市场仍不在当前范围。

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
