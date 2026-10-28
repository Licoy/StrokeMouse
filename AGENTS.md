# AGENTS.md — StrokeMouse

给人类协作者与 AI Agent 的工程说明。修改代码前请先阅读本文件与 `README.md`。

## 一句话

**StrokeMouse** 是 macOS 上的鼠标与触控板手势自定义应用：统一处理鼠标绘制、鼠标按键映射（侧键 / 中键单击）、鼠标组合（按住右键 + 滚轮 / 左键、屏幕边缘右键 / 滚轮）、触控板绘制（单修饰键 + 指针轨迹）和实验性触控手势（多指），匹配配置后执行动作。

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
| i18n | `Localizable.xcstrings`（en + zh-Hans + zh-Hant + ko + ja + ru + fr） |
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
Services: GestureRuntime, ScrollEngine, ActionExecutor, ConfigStore, PermissionManager
        ↓
Platform: MouseEventTap, ModifierEventTap, ScrollEventTap, TrackpadClickEventTap,
          MultitouchSupport bridge,
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
    Settings/                 # 手势 / 滚动 / 通用 / 权限 / 关于
    GestureEditor/            # 编辑 profile、录制轨迹、选动作
    Onboarding/               # 首次引导
  Core/
    EventTap/                  # 鼠标 filtering tap + 修饰键 listen-only tap + 触控点按 tap
    Scroll/                    # 滚动增强：分类、平滑驱动、按需 scroll tap
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

1. **用户可见文案**必须走 `String(localized:)` / String Catalog，同时提供 **en**、**zh-Hans**、**zh-Hant**、**ko**、**ja**、**ru**、**fr**。
2. **中文 UI 提示断句**：hint / help / caption / empty subtitle / footer / warning 等短提示中，同一条提示内的并列或承接分句使用 **逗号（，）或分号（；）**，不要用 **句号（。）** 把短提示拆成多句。句号仅用于提示真正结束，或长文案中语义独立的段落 / 列表项。英文保持正常句号习惯。  
   - 反例：`为此应用添加手势。在此新建的手势会默认绑定该应用。`  
   - 正例：`为此应用添加手势，在此新建的手势会默认绑定该应用。`
3. **产品对外名称**（UI / 用户文档）：「鼠标绘制」「鼠标按键」（按键映射）「鼠标组合」「触控板绘制」「触控手势」。其中「触控板绘制」对应单修饰键 + 指针轨迹；「修饰按键」选择器标签保持不变。工程代码与技术描述仍可用 modifier / multitouch 等术语。触控手势中「轻点」指只触碰不按下（`tap`），「点按」指物理按下触控板（`click`），中文 UI 不再用「单击 / 双击」描述轻点。
4. 新配置字段加入 `ConfigModels` 时保持 `Codable` 向后兼容（缺省值 / 可选字段）。新增 `GestureInputKind` 无需迁移：应用策略里覆盖首版三类且不带 `exact` 标记的抑制列表即「全部停用」，解码时自动包含新类型；只有覆盖这三类的部分选择才写入 `exact`。
5. 主线程：UI 与 `@MainActor` Service（`ConfigStore`、`GestureRuntime`、`ScrollEngine`、`AppState`）；耗时脚本用 `async` 后台。
6. 避免无关大重构；改动聚焦需求。
7. 权限失败要可观测（菜单栏状态文案 / 权限页），不要静默失败。
8. Shell / AppleScript 视为高权限能力，UI 需保留风险提示。

## 权限与安全注意

- `MouseEventTap` 依赖 `AXIsProcessTrusted()`；未授权时不得假装在监听。
- `MouseEventTap` 使用 `.defaultTap`，只捕获已配置触发键且由它收到 down 的 down/up。前台 App 不会收到配对的 down/up，因此不得出现或选中右键菜单。未达到 `minStrokeDistance` 的短按必须用带 `.eventSourceUserData` 标记的合成 down/up 回放，标记事件直接放行且不得重入手势引擎；例外一是冻结目标存在该按键的鼠标按键映射，此时短按执行映射且不回放；例外二是右键移动归拖动滚动所有时，位移达到固定 10pt 的 `MouseDragScrollSession.deadzone` 即开始滚动且不回放，未达到时仍回放。未监控按钮和没有配对 down 的事件始终放行。左键默认放行：仅当已启用的鼠标绘制 profile 存在 `secondaryAction`，或存在「按住右键 + 左键」鼠标组合时，left down/up 才进入同一 tap 掩码（在无会话时重装 tap 切换）；且只有本次会话的候选含第二动作或该组合时，触发键按住期间的 left down 与其配对 up 才被成对吞掉，组合优先于第二动作。触发键之前已按下的左键保留其 up；新的 left down 清除遗留的待吞 up。leftMouseDragged 同样不得进入掩码。
- `MouseEventTap` 仅在存在已启用的滚轮鼠标组合时把 `scrollWheel` 加入掩码（无会话时重装 tap 切换）。只有无 `eventSourceUserData` 标记、scroll / momentum phase 均为 0 的设备滚轮参与判断：按住右键时只吞会话候选含该方向组合的刻度；边缘滚轮不占用 session gate，只用 `GestureSessionGate.transientAdmission` 冻结配置，按未过滤作用域的配置先吞下，再在独立队列解析目标。被吞的刻度要么执行组合，要么回放，不得丢失；回放必须按原增量新建事件并带 `combinationReplayMarker`，不得重投原事件副本（其 `location` 已过期）。右键按下在 AX 目标查询前先做纯位置过滤，只有边缘组合可用的按下在其他位置直接放行。
- **禁止**把 `mouseMoved` 或任何 `mouseDragged` 放进 filtering tap 的 `eventsOfInterest`：`.defaultTap` 会同步拦截系统光标更新，在 macOS 14 上可导致按住触发键后光标冻结、退出 App 才恢复。所有连续移动事件必须完全绕过 event tap；路径只用 `GestureRuntime` 的 120Hz timer + `NSEvent.mouseLocation` 采样，起点与终点用 down/up 事件自身坐标（Quartz→AppKit 转换）补齐。
- `ModifierEventTap` 必须保持 listen-only，只监听 `flagsChanged`；仅支持 Fn / Control / Option / Shift / Command 中**精确的单个键**，出现额外支持键立即取消。不得吞掉键盘事件，短路径不执行动作，轨迹仍由 120Hz 指针采样获得。
- `ScrollEventTap` 的掩码只含 `scrollWheel`。回调内禁止 AX、NSWorkspace、IPC 或主线程同步调用；经 `MouseCombinationScrollBridge` 调用的 `MouseEventTap` 滚轮判断同样只读加锁状态，后续工作全部异步。滚动增强前先经该 bridge 询问鼠标组合是否消费此刻度（与两个 tap 的安装顺序无关），反向前给设备事件打 `combinationInspectedMarker`，避免另一个 tap 把反向后的事件当成反方向组合。合成滚动事件必须带 `eventSourceUserData` 标记，命中后直接放行，并投递到 `.cgSessionEventTap`，不得投到 HID。不得写入 `location`：创建时已带当前光标，过期坐标会被系统当成指针位置。tap 仅在总开关、至少一项滚动功能、辅助功能已授权时安装；不受手势暂停和 `GestureRuntime.suppress` 影响。滚动偏好只存本机 `UserDefaults`，不进入 `PortableSettingsV1`。
- `TrackpadClickEventTap` 的掩码只含 left down/up，不得加入 `leftMouseDragged` 或其他移动事件。回调只访问加锁状态（`TrackpadPressArbiter`），禁止 AX、NSWorkspace、IPC 或主线程同步调用。存在已启用的点按 profile 或诊断进行中时以 `.defaultTap` 安装；只有轻点 profile 时为 listen-only，仅标记按下过的序列；其他情况不安装。它依赖 multitouch 通道处于监听且辅助功能已授权，失败时通过 `trackpadClick` 通道状态可见。只有触点仍在、手指数已按冻结目标 arm、无抬起、落指间隔不超过 `maximumLandingSpread` 且位移不超过 `maximumPressTravel` 的按下才算点按并吞掉；吞掉的 down 必须同时吞掉配对 up，新的 down 清除遗留的待吞 up，带回放标记的事件直接放行。
- Event tap 的 CFRunLoop source 跑在**专用线程**（非主线程），避免 UI/主线程卡顿拖死光标投递。
- 触控手势（多指）只允许通过本地 C bridge `dlopen` / `dlsym` 解析 `MultitouchSupport`；禁止静态链接私有框架或引入第三方二进制。私有 callback 必须先复制成稳定值，再送入 Swift 串行队列；stop/unregister 后不得留下悬空 callback。
- 触控手势不拦截 macOS 原生手势，系统动作可能同时发生；唯一例外是点按手势吞掉对应的物理左键 down/up。不得保存或记录原始触点轨迹；私有后端失败只将 multitouch 通道标为 failed/degraded，不能拖垮 mouse / modifier 通道，也不得模拟回退或静默重试。
- Entitlements：`app-sandbox = false`，`automation.apple-events = true`。
- 勿在日志中打印用户脚本全文到公开渠道。

## 手势识别要点

1. 输入统一保存在 `GestureProfile.input`：`.drawn` 包含鼠标或单修饰键 activation 与 points；`.trackpad` 包含手指数、family 和方向 / 次数；`.mouseButton` 含按键（侧键后退 / 前进、中键，右键不可映射）与可选的单个修饰键
2. 鼠标或修饰键按下 → 采样路径 → 位移超过 `minStrokeDistance` 才算有效；鼠标短按回放点击，修饰键短路径直接结束
3. 绘制结束 → 仅在同 activation 的候选中匹配：
   - `freePath`：每条手势保存 1–5 个样本（建议 3 个），各样本独立匹配并取最高分；新录制先按弧长重采样为 128 点，再统一归一化
   - 所有绘制样本统一走 `ElasticPathMatcher`：64 点弧长重采样 + 轻度平滑，按主轴厚度平滑切换等比 / 分轴归一化，首尾锚定、`±12.5%` 带宽、斜率 1/2–2 的弹性对齐；局部代价以平方切线差为主、位置为辅，再对 15% 弧长窗口内超过下限的集中偏差加罚，分数 `exp(-d / 0.32)`
   - 不再使用结构门控或曲线 / 折线分通道：自然抖动、端点小钩、比例变化连续降分，反向、镜像、截断、明显多画的尾巴因代价过高被拒绝；不使用开放头尾、镜像、逆序或 near-miss 兜底
   - 实时 HUD 用 32 点粗剖面比较整条模板及其 10%–80% 前缀，先用平均代价下界剪枝，再算完整距离；终态识别不使用前缀
   - 调整参数前用 `Issue17LetterRecognitionTests`（Issue #17 真实字母轨迹）与各录制 fixture 回归，详见 `docs/elastic-path-recognition.md`
4. 鼠标绘制可选 `GestureProfile.secondaryAction`：会话中点击过左键则只执行匹配手势的第二动作，匹配手势没有第二动作时不执行任何动作（`secondaryActionUnavailable`）；所有候选仍参与匹配，左键只选择动作；未达到有效轨迹的左键会话直接取消、不回放点击；触控板绘制与触控手势始终执行主动作
5. 鼠标按键映射复用 mouse 会话与 `MouseEventTap`，不新增 tap 或掩码：按住期间位移未达 `minStrokeDistance` 时在松开执行映射，超过则走绘制识别、不执行映射；冻结目标没有该按键的绘制候选时不采样、不显示 HUD，松开即按单击执行。只取最具体作用域层（应用 > 应用组 > 全局），同层多条为冲突，执行零个动作并提示；成功不弹匹配提示。全局映射受 `GestureInputKind.mouseButton` 抑制，与鼠标绘制分开。修饰键取自按下事件自身的 flags（`shouldCapture` 第三个参数，经 `ModifierEventTap.supportedKeys` 换算），在 tap 线程决定捕获前过滤候选：按住的支持键集合必须与映射配置的修饰键（或空集）完全相等，绘制候选不看修饰键；所选修饰键若同时用于触控板绘制，modifier 会话先占用 session gate，映射不会触发
6. 鼠标组合保存在 `GestureInput.mouseCombination`：「按住右键 + 滚轮 / 左键」复用右键 mouse 会话与冻结目标，触发后松开右键不再识别绘制、不回放点击，左键每次按住只触发一次，普通滚轮每格触发、高精度（continuous）滚轮按事件时间戳限频 120ms；「边缘 + 右键」在未开始绘制且松开时仍在所选边缘时执行；「边缘 + 滚轮」按处理时间限频 100ms，未命中作用域时回放。作用域优先级与冲突规则同鼠标按键映射，全局组合受 `GestureInputKind.mouseCombination` 抑制。边缘为各显示器 Quartz 边界内 3 点，相邻显示器接缝也算边缘
7. 触控手势支持 40 类：三至五指轻点 / 轻点两下 / 点按 / 点按两下 / 四向滑动，以及二至五指捏合 / 张开 / 顺逆时针旋转；混合变换、对角滑动和 near-miss 必须拒绝。物理按下过触控板的触点序列不得识别为任何轻点 / 滑动等触控手势（`.physicallyPressed`）；点按在按下时执行，单 / 双次由独立的 `clickResolver` 判定，截止计时不因触点序列进行中而顺延
8. mouse / modifier / multitouch 通过同一 session gate 仲裁；第一个合法 begin 冻结配置 revision、候选 profile、目标应用和精确窗口，其他来源忽略到物理输入归零；单个边缘滚轮刻度不是会话，不得占用 gate
9. 使用冻结应用的 `bundleIdentifier` 过滤 `AppScope`；触控手势中应用专属配置优先于全局，同级多个精确匹配视为冲突并执行零个动作；命中动作始终复用冻结目标

10. 拖动滚动保持 `mouseCombination.dragScroll` 输入，沿用右键会话与指针采样，不增加 filtering tap 移动掩码；固定从指针下内容开始，不激活冻结窗口，松手 / 取消 / 暂停立即停止，无惯性或光标锁定，合成滚轮带标记且不进入滚动增强。移动模式先按最具体作用域选择，同级拖动滚动与右键绘制或多条拖动滚动冲突时零执行，并使用独立的移动冲突提示；确定冲突（相同全局、应用列表相交、同一应用组）由 `MouseMovementConflict` 在所有 UI 入口拦截：编辑器按草稿作用域检查，列表启用 / 批量启用、移动、删除应用组并转为全局时拒绝并列出冲突手势，复制出的冲突副本与导入的冲突手势以停用状态加入，已存在的冲突在列表中显示警告；不自动停用或删除已有绘制
11. 系统动作使用独立 `system` 语义与可选快捷键覆盖，应用程序窗口沿冻结目标，其余系统导航保持当前系统上下文，普通快捷键仍激活冻结目标；编辑器读取 `com.apple.symbolichotkeys` 提示系统快捷键已关闭或与此处不一致，未设置覆盖且系统条目已关闭时执行报错，不静默失败；主动作或第二动作包含最大化窗口的配置 / 导出使用 v5，否则包含系统动作或拖动滚动时使用 v4，只有 Fn 快捷键时 v3，其他配置 v2

调参常量见 `Constants.swift`。

## 触控板支持范围与限制

- 已支持鼠标绘制、触控板绘制（Fn / Control / Option / Shift / Command 单键 + 指针轨迹），以及实验性触控手势总开关；关闭总开关不得删除 profile。
- 40 类触控手势 = 三至五指轻点 / 轻点两下（6）+ 三至五指点按 / 点按两下（6）+ 三至五指四向滑动（12）+ 二至五指捏合 / 张开（8）+ 二至五指顺逆时针旋转（8）。
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
