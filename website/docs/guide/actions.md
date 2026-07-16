---
title: "动作类型"
description: "StrokeMouse 支持的动作：快捷键、打开 App、URL、媒体键、窗口操作、Shell 与 AppleScript。"
titleTemplate: "StrokeMouse"
---

# 动作类型

匹配成功后，`ActionExecutor` 按配置分发动作。以下为当前支持的类型。

## 一览

| 类型 | 说明 | 注意 |
|------|------|------|
| 无动作 | 仅用于测试匹配 | — |
| **快捷键** | 注入系统快捷键（含修饰键） | 依赖辅助功能 |
| **打开 App** | 按 bundle id / 名称启动应用 | 需填写正确 bundle id |
| **打开 URL** | 用默认浏览器打开链接 | — |
| **媒体键** | 播放暂停、上下曲、音量、静音 | — |
| **窗口操作** | 关闭、最小化、缩放、全屏、隐藏、居中 | 依赖 AX |
| **Shell** | 执行 shell 命令 | **高权限** |
| **AppleScript** | 运行 AppleScript | **高权限**，可能需自动化权限 |

## 快捷键

在编辑器中录制或填写键码与修饰键。显示名（如 `⌃↑`）便于在列表中辨认。

典型用途：Mission Control、切换桌面、App 内快捷键等。

## 打开应用

通过 **bundle identifier** 定位应用，例如：

- Safari：`com.apple.Safari`
- 终端：`com.apple.Terminal`

名称字段主要用于界面展示。

## 打开 URL

任意 `https://` / `http://` 等系统可处理的 URL。默认手势中的「打开 GitHub」即此类型。

## 媒体键

| 命令 | 作用 |
|------|------|
| playPause | 播放 / 暂停 |
| nextTrack / previousTrack | 下一曲 / 上一曲 |
| volumeUp / volumeDown / mute | 音量与静音 |

## 窗口操作

| 命令 | 作用 |
|------|------|
| close | 关闭窗口 |
| minimize | 最小化 |
| zoom | 缩放（绿键语义） |
| fullscreen | 全屏 |
| hide | 隐藏应用 |
| center | 窗口居中 |

目标通常为当前前台窗口；若 AX 不可用可能失败，请确认辅助功能已授权。

## Shell

执行本地 shell 命令字符串。

::: danger 风险
Shell 拥有与当前用户相当的文件系统与进程权限。恶意或误写命令可造成数据损失。请只粘贴你理解且信任的命令。
:::

## AppleScript

运行脚本文本。控制其他 App 时，系统可能要求 **自动化** 权限。

::: danger 风险
与 Shell 类似，具有自动化与脚本执行能力。勿运行来源不明的脚本。
:::

## 选择建议

| 目标 | 推荐动作 |
|------|----------|
| 系统 / App 快捷键 | 快捷键 |
| 启动某软件 | 打开 App |
| 网页书签式跳转 | 打开 URL |
| 音乐与音量 | 媒体键 |
| 窗口管理 | 窗口操作 |
| 高度自定义 | Shell / AppleScript（慎用） |

配置持久化见 [配置文件](./config-file)。
