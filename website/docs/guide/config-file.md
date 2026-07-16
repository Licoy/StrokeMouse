---
title: "配置文件"
description: "StrokeMouse 配置文件路径与备份：~/Library/Application Support/StrokeMouse/gestures.json。"
titleTemplate: "StrokeMouse"
---

# 配置文件

手势与相关偏好以 **JSON** 持久化，便于备份、同步（手动）与高级编辑。

## 路径

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

设置界面可「在 Finder 中显示」该目录。

## 使用建议

| 场景 | 做法 |
|------|------|
| 备份 | 复制整个 `StrokeMouse` 目录或单独复制 `gestures.json` |
| 换机 | 装好 App 并授权后，覆盖同名文件再启动 |
| 手工编辑 | 保持合法 JSON；未知字段应尽量向后兼容（缺省值 / 可选） |
| 损坏恢复 | 可删掉文件让应用重新生成默认配置（会丢失自定义） |

::: warning
应用运行时可能写回配置。请在退出 App 或确认无并发写入时再覆盖文件。
:::

## 配置里大致有什么

每条手势（profile）通常包含：

- 唯一 id、名称、是否启用
- **触发键**（右 / 中 / 侧键等）
- **轨迹**（自由路径点列；旧版方向序列仍可解码并转换）
- **动作**（快捷键、App、URL、媒体、窗口、Shell、AppleScript 等）
- **作用域**（全局或 bundle id 列表）
- 备注

具体字段以应用版本的 `Codable` 模型为准；升级后旧文件应尽量可读。

## 与 UI 的关系

日常请优先用 **设置 → 手势** 编辑。JSON 适合：

- 批量备份
- 在版本库中保存个人配置（注意勿提交含隐私的脚本）
- 排查损坏的配置

## 隐私

Shell / AppleScript 内容可能含路径或令牌。分享配置文件前请自行脱敏。
