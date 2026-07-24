<div align="center">
  <img src="design/logo/stroke-mouse-app-icon.png" width="128" alt="StrokeMouse" />
  <h1>StrokeMouse</h1>
  <p>
    <b>中文</b> · <a href="./README_EN.md">English</a>
  </p>
  <p>
    <a href="./LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/License-AGPL%20v3-blue.svg" /></a>
  </p>
</div>

macOS 鼠标手势自定义工具。按住**该手势的触发键**（默认右键，也可中键 / 侧键）绘制轨迹，匹配后执行快捷键、打开应用、窗口操作、媒体键、Shell / AppleScript 等。支持**全局或指定 App** 生效，手势配置可**导入导出**，本地运行、菜单栏常驻。

## 界面预览

| 手势配置列表 | 手势测试 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/1.png" width="400" alt="手势配置列表" /> | <img src="website/docs/public/screenshots/2.png" width="400" alt="手势测试" /> |

| 通用设置 | 权限与引擎状态 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/3.png" width="400" alt="通用设置" /> | <img src="website/docs/public/screenshots/4.png" width="400" alt="权限与引擎状态" /> |

| 新建手势 · 录制轨迹 | 应用范围 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/5.png" width="400" alt="新建手势 · 录制轨迹" /> | <img src="website/docs/public/screenshots/6.png" width="400" alt="应用范围" /> |

## 功能

- **菜单栏常驻**：启停手势、打开设置、退出；图标随状态变色（正常 / 暂停 / 缺权限）；可**隐藏菜单栏图标**（与隐藏 Dock 同时开启会二次确认；隐藏后点 Dock 或再开 App 进入设置）
- **手势库管理**：侧栏按**全局 / 各 App** 组织（新建时预填作用域）；搜索 / 筛选 / 排序；多选批量启停删除；**JSON 导入导出**（重复项可跳过或强制导入）
- **每条手势独立触发键**：默认右键；中键 / 侧键可选；只监听已启用触发键
- **每条手势独立目标**：可选按下触发键时的当前前台应用或指针位置所属应用；若存在普通窗口则同时锁定精确窗口，应用范围判断与目标相关动作始终复用该目标
- **自由轨迹识别**：有序弧长重采样 + 1D/2D 归一化 + 有限旋转；显著转折结构门控；可在通用设置调整全局匹配阈值；按住触发键时实时轨迹 HUD
- **App 作用域**：全局，或从已安装应用中选图标添加（支持搜索 / 浏览 `.app`）
- **多种动作**：快捷键、打开 App（图标选择器）、URL、媒体键、窗口操作、Shell / AppleScript（语法高亮；AppleScript 含睡眠、锁屏、清废纸篓等预设与自定义）
- **体验**：中英界面、深浅色（跟随系统 / 强制）、登录启动、隐藏 Dock / 菜单栏图标、Sparkle 应用内更新（失败可回落 GitHub Releases）

## 系统要求

- macOS 14 Sonoma 或更高
- Xcode 16+（开发构建）
- 任意鼠标即可（默认手势使用右键触发；可在手势编辑中改为中键等）

## 权限

| 权限 | 用途 |
|------|------|
| **辅助功能（Accessibility）** | 全局鼠标事件监听（CGEventTap）、快捷键注入、窗口 AX 操作 |
| **自动化（Automation）** | 可选；AppleScript 控制其他 App 时按需授权 |

首次启动或 **设置 → 权限** 可使用应用内**引导授权**：打开系统设置并拖入 StrokeMouse 完成开关。未授权时引擎不会假装在监听。

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

固定产出到仓库下 `output/StrokeMouse.app`，路径稳定，减少重复授权辅助功能。  
Debug 显示名为 **StrokeMouse Dev**（Bundle ID `com.strokemouse.app.dev`），与正式版 **StrokeMouse** 可同时在辅助功能中授权，互不冲突：

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app（辅助功能中显示 StrokeMouse Dev）
./scripts/build.sh --open    # 编译完成后自动打开
./scripts/build.sh --release # Release（显示名 / Bundle ID 与正式包一致）
```

### 发布打包

按架构生成 ZIP、TAR.GZ 和 DMG，并验证签名、entitlements 与产物完整性（默认用固定自签身份 **`StrokeMouse Release`**，便于辅助功能跨 Sparkle 更新保留）：

```bash
# 首次本地：./scripts/generate-codesign-cert.sh --import
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

发布与 CI secrets 说明见 `RELEASING.md` / `certs/README.md`。

版本发布使用 `./bump.sh -v x.y.z [-p]`；同版本重打 tag 并推送用 `./bump.sh -v x.y.z --force`。

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

> **短按 vs 手势**：触发键的按下与松开由手势引擎暂时捕获；未达到「最小滑动距离」便松开时会回放为正常点击，右键菜单仍可用。所有鼠标移动与拖动事件都会直接交给系统更新光标，手势引擎通过定时采样记录轨迹；前台 App 收不到配对的触发键按下与松开，因此绘制时不会打开或选中右键菜单。左键和未配置为触发键的鼠标按钮不受影响。

> 快捷键会先激活锁定应用；若锁定了精确窗口，也会将该窗口置前，因此可能切换焦点或桌面空间。Finder 桌面等没有普通窗口的位置仍可执行快捷键和「隐藏应用」；关闭、最小化、缩放、全屏、居中仍需要精确窗口。短按不会激活目标。

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

日常可用 **设置 → 手势** 多选后导出 / 导入 JSON 包。整库可复制上述文件备份或手工编辑（需保持结构合法）。设置页可「在 Finder 中显示」。

## 技术栈

- Swift / SwiftUI（macOS 14+）
- 轻量 MVVM + Service
- `CGEventTap` 全局鼠标事件
- JSON 配置持久化
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) 登录启动
- [Sparkle](https://github.com/sparkle-project/Sparkle) 签名校验与应用内更新
- XcodeGen 管理工程

## 许可与免责

本项目采用 [GNU Affero General Public License v3.0 (AGPL-3.0)](./LICENSE) 开源。

本地工具，全局事件与脚本动作具有系统级能力。请仅添加你信任的 Shell / AppleScript。作者不对误操作或权限滥用负责。
