---
title: "安装与构建"
description: "StrokeMouse 安装与源码构建说明：系统要求 macOS 14+、命令行构建、Xcode 运行、签名与测试。"
titleTemplate: "StrokeMouse"
---

# 安装与构建

优先从 [下载页](/download) 获取 **Apple Silicon / Intel** 生产构建。若需要自行编译，可按下方从源码构建。

## 系统要求

| 项 | 要求 |
|----|------|
| 系统 | macOS 14 Sonoma 或更高 |
| 开发构建 | Xcode 16+ |
| 工程生成 | [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`） |

## 获取源码

```bash
git clone https://github.com/Licoy/StrokeMouse.git
cd StrokeMouse
```

## 推荐：命令行构建

固定产出到仓库下 `output/StrokeMouse.app`，路径稳定，有助于减少反复授权辅助功能。  
Debug 在辅助功能中显示为 **StrokeMouse Dev**（Bundle ID `com.strokemouse.app.dev`），可与正式版 **StrokeMouse** 同时授权：

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app（辅助功能：StrokeMouse Dev）
./scripts/build.sh --open    # 编译完成后自动打开
./scripts/build.sh --release # Release（显示名 / Bundle ID 与正式包一致）
```

首次或在改动 `project.yml` / 增删源文件后，生成 Xcode 工程：

```bash
./scripts/generate_project.sh
```

## 在 Xcode 中运行

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

选择 Scheme **StrokeMouse**，Run 即可。

## 签名说明

| 项 | 值 |
|----|-----|
| Bundle ID | Release：`com.strokemouse.app`；Debug：`com.strokemouse.app.dev`（显示名 StrokeMouse Dev） |
| 开发签名 | 本机钥匙串中的 **`StrokeMouse Dev`**（自签证书，需在钥匙串中信任代码签名） |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` |
| GitHub Release | ad-hoc + Hardened Runtime，当前未经 Apple 公证 |

::: warning
更换签名身份或 Bundle 路径后，系统可能把应用视为「新应用」，需要**重新勾选辅助功能**。

GitHub Release 首次启动若被 Gatekeeper 阻止，请右键点按 App 并选择「打开」，或在「系统设置 → 隐私与安全性」中选择「仍要打开」。
:::

## 发布产物

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

每个架构会生成 ZIP、TAR.GZ 和 DMG；ZIP 同时用于 Sparkle 应用内更新。版本与 Tag 发布流程见仓库根目录 `RELEASING.md`。

## 测试

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## 依赖

- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) — 登录启动
- [Sparkle](https://github.com/sparkle-project/Sparkle) — 签名校验和应用内更新
- 系统框架：`CGEventTap`、Accessibility、可选 Apple Events

## 下一步

构建成功并打开 App 后，请继续 [权限说明](./permissions) 与 [快速开始](./getting-started)。
