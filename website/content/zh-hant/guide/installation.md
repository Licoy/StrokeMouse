---
title: "安裝與建置"
description: "StrokeMouse 安裝與原始碼建置說明：系統要求 macOS 14+、命令列建置、Xcode 執行、簽署與測試。"
keywords: "StrokeMouse 安裝,原始碼建置,xcodebuild,簽署,macOS 14"
---

# 安裝與建置

建議使用 Homebrew 安裝；也可從 [下載頁](/zh-hant/download) 取得 **Apple Silicon / Intel** 正式建置。若需要自行編譯，可依下方從原始碼建置。

## 系統需求

| 項 | 要求 |
|----|------|
| 系統 | macOS 14 Sonoma 或更高 |
| 開發建置 | Xcode 16+ |
| 工程產生 | [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`） |

## Homebrew（建議）

透過 StrokeMouse 專案維護的 [Licoy Homebrew Tap](https://github.com/Licoy/homebrew-tap) 安裝：

```bash
brew install --cask licoy/tap/strokemouse
```

StrokeMouse 同時支援應用內更新；如希望透過 Homebrew 強制檢查並升級，請使用：

```bash
brew upgrade --cask --greedy strokemouse
```

解除安裝時預設保留設定，加上 `--zap` 可同時移除設定：

```bash
brew uninstall --cask strokemouse
brew uninstall --cask --zap strokemouse
```

Homebrew 安裝與手動下載使用同一份正式發行包，因此首次啟動時的 Gatekeeper 與輔助使用說明相同。

## 取得原始碼

```bash
git clone https://github.com/Licoy/StrokeMouse.git
cd StrokeMouse
```

## 建議：命令列建置

固定產出到倉庫下 `output/StrokeMouse.app`，路徑穩定，有助於減少反覆授權輔助使用。  
Debug 在輔助使用中顯示為 **StrokeMouse Dev**（Bundle ID `com.strokemouse.app.dev`），可與正式版 **StrokeMouse** 同時授權：

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app（輔助使用：StrokeMouse Dev）
./scripts/build.sh --open    # 編譯完成後自動打開
./scripts/build.sh --release # Release（顯示名 / Bundle ID 與正式包一致）
```

首次或在改動 `project.yml` / 增刪原始檔後，產生 Xcode 工程：

```bash
./scripts/generate_project.sh
```

## 在 Xcode 中執行

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

選擇 Scheme **StrokeMouse**，Run 即可。

## 簽署說明

| 項 | 值 |
|----|-----|
| Bundle ID | Release：`com.strokemouse.app`；Debug：`com.strokemouse.app.dev`（顯示名 StrokeMouse Dev） |
| 開發簽署 | 本機鑰匙圈中的 **`StrokeMouse Dev`**（自簽，本機建置用） |
| Release 簽署 | **`StrokeMouse Release`** 自簽 + Hardened Runtime（固定身分；**使用者無需安裝憑證**） |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` 或 package（僅 smoke；**更新後輔助使用會丟**） |
| 公證 | 目前未經 Apple 公證 / 無 Developer ID |

::: warning
GitHub Release 首次啟動若被 Gatekeeper 阻止，請按住 Control 點按 App 並選擇「打開」，或在「系統設定 → 隱私權與安全性」中選擇「仍要打開」。

**輔助使用**：正式包使用固定自簽身分後，**同一憑證簽出的應用內更新通常無需重新授權**。從舊 ad-hoc 包遷到自簽、或更換憑證後，仍需**重新勾選一次**。使用者**不要**手動安裝發布方憑證。
:::

## 發布產物

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

每個架構會產生 ZIP、TAR.GZ 和 DMG；ZIP 同時用於 Sparkle 應用內更新。版本與 Tag 發布流程見倉庫根目錄 `RELEASING.md`。

## 測試

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## 相依

- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) — 登入時啟動
- [Sparkle](https://github.com/sparkle-project/Sparkle) — 簽署校驗和應用內更新
- 系統框架：`CGEventTap`、Accessibility、可選 Apple Events

## 下一步

建置成功並打開 App 後，請繼續 [權限說明](./permissions) 與 [快速開始](./getting-started)。
