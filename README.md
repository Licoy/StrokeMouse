# StrokeMouse

macOS 鼠标手势自定义工具。按住**该手势配置的触发键**（默认鼠标右键，也可为中键等）绘制轨迹，匹配到手势后执行快捷键、打开应用、窗口操作、媒体键、Shell / AppleScript 等动作。

## 功能

- **菜单栏常驻**：启停手势、打开设置、权限提示、退出
- **手势配置**：增删改查、启用开关、**每条手势独立触发键**、全局 / 指定 App 作用域
- **识别方式**
  - 自由轨迹模板（有序弧长重采样 + 1D/2D 归一化 + 有限旋转 + 显著转折拒识）
  - 按住触发键时屏幕上实时绘制轨迹 HUD
- **动作类型**：快捷键、打开 App、URL、Shell、媒体键、窗口操作、AppleScript
- **体验**：深浅色（跟随系统 / 强制）、中英 String Catalog、登录启动、隐藏 Dock 图标

## 系统要求

- macOS 14 Sonoma 或更高
- Xcode 16+（开发构建）
- 任意鼠标即可（默认手势使用右键触发；可在手势编辑中改为中键等）

## 权限

| 权限 | 用途 |
|------|------|
| **辅助功能（Accessibility）** | 全局鼠标事件监听（CGEventTap）、快捷键注入、窗口 AX 操作 |
| **自动化（Automation）** | 可选；AppleScript 控制其他 App 时按需授权 |

首次启动后请到 **设置 → 权限** 完成辅助功能授权，否则手势引擎无法监听。

## 构建与运行

### 依赖

```bash
brew install xcodegen
```

### 生成工程并打开

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

或在 Xcode 中直接 **Run**（Scheme: `StrokeMouse`）。

### 命令行构建（推荐）

固定产出到仓库下 `output/StrokeMouse.app`，路径稳定，减少重复授权辅助功能：

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app
./scripts/build.sh --open    # 编译完成后自动打开
./scripts/build.sh --release # Release
```

### 签名

- Bundle ID：`com.strokemouse.app`
- 开发签名身份：本机钥匙串中的 **`StrokeMouse Dev`**（自签证书，需在「钥匙串访问」中信任代码签名）
- 可覆盖：`CODE_SIGN_IDENTITY="-" ./scripts/build.sh`（ad-hoc）
- GitHub Release 使用 ad-hoc + Hardened Runtime，当前不做 Apple 公证

### 发布打包

按架构生成 ZIP、TAR.GZ 和 DMG，并验证签名、entitlements 与产物完整性：

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

版本发布使用 `./bump.sh -v x.y.z [-p]`；完整的 Sparkle 密钥、Secrets 和 Tag Release 流程见 [RELEASING.md](./RELEASING.md)。

### 测试

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## 使用说明

1. 启动应用，菜单栏出现鼠标图标  
2. 授予 **辅助功能** 权限，并在菜单栏选择「恢复手势」/ 确认已启用  
3. 打开 **设置 → 手势**，查看默认手势或新建  
4. 按住该手势的 **触发键**（默认右键；可在编辑手势时改为中键等），画出路径后松开  
5. 匹配成功后执行绑定动作  

> **短按 vs 手势**：触发键的按下与松开由手势引擎暂时捕获；未达到「最小滑动距离」便松开时会回放为正常点击，右键菜单仍可用。开始绘制后，拖动事件仍会更新系统游标和手势轨迹，但前台 App 收不到配对的按下与松开，因此不会打开或选中右键菜单。左键和未配置为触发键的鼠标按钮不受影响。


默认手势示例（均默认右键触发；不同手势可绑定不同按键）：

| 手势 | 动作 |
|------|------|
| ↑ | Mission Control（⌃↑） |
| ↓ | 应用程序窗口（⌃↓） |
| ↓← | 最小化窗口 |
| ↓→ | 关闭窗口 |
| ↑→ | 打开 Safari |
| →← | 播放 / 暂停 |
| ↑← | 打开 GitHub |

## 配置文件

路径：

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

JSON 可备份、可手工编辑（需保持结构合法）。设置页可「在 Finder 中显示」。

## 项目结构（概要）

```text
StrokeMouse/
  App/                 # 入口、AppState
  Features/            # 菜单栏、设置、编辑器、引导
  Core/                # EventTap、识别、动作、配置、权限
  Resources/           # 资源、Localizable.xcstrings
  Supporting/          # Entitlements、常量
StrokeMouseTests/      # 单元测试
scripts/               # 工程生成与发布脚本
project.yml            # XcodeGen 定义
AGENTS.md              # 给协作者 / AI Agent 的工程说明
```

更完整的目录与约定见 [AGENTS.md](./AGENTS.md)。

## 技术栈

- Swift / SwiftUI（macOS 14+）
- 轻量 MVVM + Service
- `CGEventTap` 全局鼠标事件
- JSON 配置持久化
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) 登录启动
- [Sparkle](https://github.com/sparkle-project/Sparkle) 签名校验与应用内更新
- XcodeGen 管理工程

## 路线图（非承诺）

- [ ] 屏幕手势轨迹 HUD
- [ ] 更强的快捷键录制与键名展示
- [x] Sparkle 自动更新
- [ ] 链式动作 / 条件触发
- [ ] 触控板相关能力（可选）

## 许可与免责

本地工具，全局事件与脚本动作具有系统级能力。请仅添加你信任的 Shell / AppleScript。作者不对误操作或权限滥用负责。
