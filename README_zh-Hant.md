[English](./README.md) · [简体中文](./README_zh-Hans.md) · **繁體中文** · [한국어](./README_ko.md) · [日本語](./README_ja.md) · [Русский](./README_ru.md) · [Français](./README_fr.md)

<div align="center">
  <img src="design/logo/stroke-mouse-app-icon.png" width="128" alt="StrokeMouse" />
  <h1>StrokeMouse</h1>
  <p>
    <a href="./LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/License-AGPL%20v3-blue.svg" /></a>
  </p>
</div>

macOS 滑鼠與觸控式軌跡板手勢自訂工具。可按住滑鼠鍵繪製軌跡、按住單一修飾鍵進行觸控板繪製，也可使用實驗性的多指觸控手勢；比對成功後執行快捷鍵、開啟應用程式、視窗操作、媒體鍵、Shell / AppleScript 等。支援**全域或指定 App** 生效，手勢設定可**匯入匯出**，本機執行、選單列常駐。

## 介面預覽

| 手勢設定列表 | 手勢測試 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/1.png" width="400" alt="手勢設定列表" /> | <img src="website/docs/public/screenshots/2.png" width="400" alt="手勢測試" /> |

| 一般設定 | 權限與引擎狀態 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/3.png" width="400" alt="一般設定" /> | <img src="website/docs/public/screenshots/4.png" width="400" alt="權限與引擎狀態" /> |

| 新增手勢 · 錄製軌跡 | 應用範圍 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/5.png" width="400" alt="新增手勢 · 錄製軌跡" /> | <img src="website/docs/public/screenshots/6.png" width="400" alt="應用範圍" /> |

## 功能

- **選單列常駐**：啟停手勢、開啟設定、結束；圖示隨狀態變色（正常 / 暫停 / 缺權限）；可**隱藏選單列圖示**（與隱藏 Dock 同時開啟會二次確認；隱藏後點 Dock 或再開 App 進入設定）
- **手勢庫管理**：側邊欄依**全域 / 各 App** 組織（新增時預填範圍）；搜尋 / 篩選 / 排序；多選批次啟停刪除；**JSON 匯入匯出**（重複項可略過或強制匯入）
- **滑鼠繪製**：每條手勢可獨立選擇右鍵、中鍵或側鍵，只監聽已啟用設定用到的按鈕
- **觸控板繪製**：按住一個 Fn / Control / Option / Shift / Command（預設 Fn）後移動指標繪製；必須精確按住單一支援鍵，額外修飾鍵會取消本次辨識
- **實驗性觸控手勢**：內建觸控式軌跡板支援 34 類三至五指輕觸 / 點兩下 / 四向滑動，以及二至五指捏合 / 張開 / 順逆時針旋轉
- **觸控手勢總開關**：可隨時關閉觸控手勢通道而不刪除已設定手勢；私有後端故障只降級觸控通道，不影響滑鼠與觸控板繪製
- **捲動增強**：滑鼠滾輪與觸控板 / 巧控滑鼠的縱向、橫向可分別反向，一般滾輪還可選平滑捲動（柔和 / 標準 / 靈敏，或自訂速度、時長與加速）；排除清單以前景應用程式判斷，設定只留在本機，不進入備份同步；與其他捲動工具同時運行可能被處理兩次，只讀取整數行增量的應用程式（部分遊戲、虛擬機、遠端桌面）請加入排除清單
- **每條手勢獨立目標**：可選按下觸發鍵時的目前前景應用程式或指標位置所屬應用程式；若存在一般視窗則同時鎖定精確視窗，應用範圍判斷與目標相關動作始終重用該目標
- **自由軌跡辨識**：有序弧長重採樣 + 1D/2D 正規化 + 有限旋轉；顯著轉折結構門檻；可在一般設定調整全域比對閾值；按住觸發鍵時即時軌跡 HUD
- **App 範圍**：全域，或從已安裝應用程式中選圖示新增（支援搜尋 / 瀏覽 `.app`）
- **多種動作**：快捷鍵、開啟 / 切換 App、URL、媒體鍵、視窗操作、Shell / AppleScript（語法醒目提示；AppleScript 含睡眠、鎖定螢幕、清空廢紙簍等預設與自訂）
- **體驗**：介面支援英語、簡體中文、繁體中文、韓語、日語、俄語、法語（也可跟隨系統語言），深淺色（跟隨系統 / 強制）、登入時啟動、隱藏 Dock / 選單列圖示、Sparkle 應用內更新（失敗可回落到 GitHub Releases）

## 系統需求

- macOS 14 Sonoma 或更高
- Xcode 16+（開發建置）
- 滑鼠或觸控式軌跡板均可完成繪製手勢；直接多指觸控優先支援 Mac 內建觸控式軌跡板
- 外接 Magic Trackpad 為 best-effort 支援，可能因機型或系統版本而異

## 安裝

### Homebrew（建議）

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

也可前往 [官網下載頁](https://strokemouse.com/zh-hant/download) 手動下載對應架構的 DMG。目前發行版使用固定自簽程式碼簽署且未經 Apple 公證；首次啟動若被 Gatekeeper 阻擋，請按住 Control 點按 App 並選擇「打開」，或在「系統設定 → 隱私權與安全性」中選擇「仍要打開」。

## 權限

| 權限 | 用途 |
|------|------|
| **輔助使用（Accessibility）** | 全域滑鼠 / 修飾鍵 / 捲動事件監聽（CGEventTap）、快捷鍵注入、視窗 AX 操作 |
| **自動化（Automation）** | 可選；AppleScript 控制其他 App 時按需授權 |

首次啟動或 **設定 → 權限** 可使用應用內**引導授權**：開啟系統設定並將 StrokeMouse 拖入清單完成開關。未授權時引擎不會假裝在監聽。

### 實驗性觸控手勢

觸控手勢透過執行時期 `dlopen` / `dlsym` 載入 Apple 未公開的 `MultitouchSupport`，不靜態連結該私有框架。它可能在 macOS 更新後失效；缺少框架、符號、裝置或裝置啟動失敗都會顯示為觸控通道故障，滑鼠與觸控板繪製仍可繼續使用，不會模擬回退或靜默重試。

StrokeMouse 不會攔截觸控式軌跡板原生事件，因此系統手勢可能與綁定動作同時發生。應用程式也不會儲存或記錄原始觸點軌跡。第一次儲存、啟用或匯入已啟用的觸控手勢設定時會顯示實驗風險確認；之後可用總開關暫停觸控手勢而不刪除設定。

支援的 34 類觸控手勢：

| 類別 | 手指數 | 變體 | 數量 |
|------|--------|------|------|
| 輕觸 | 三 / 四 / 五指 | 單擊、點兩下 | 6 |
| 滑動 | 三 / 四 / 五指 | 上、下、左、右 | 12 |
| 縮放 | 二 / 三 / 四 / 五指 | 捏合、張開 | 8 |
| 旋轉 | 二 / 三 / 四 / 五指 | 逆時針、順時針 | 8 |
| **合計** |  |  | **34** |

首版不支援兩指輕觸 / 滑動、修飾鍵組合、特定手指身分、連續重複動作或使用者調整辨識閾值。

## 建置與執行

### 相依套件

```bash
brew install xcodegen
```

### 產生專案並開啟

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

或在 Xcode 中直接 **Run**（Scheme: `StrokeMouse`）。

### 命令列建置（建議）

固定產出到倉庫下 `output/StrokeMouse.app`，路徑穩定，減少重複授權輔助使用。  
Debug 顯示名稱為 **StrokeMouse Dev**（Bundle ID `com.strokemouse.app.dev`），與正式版 **StrokeMouse** 可同時在輔助使用中授權，互不衝突：

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app（輔助使用中顯示 StrokeMouse Dev）
./scripts/build.sh --open    # 編譯完成後自動開啟
./scripts/build.sh --release # Release（顯示名稱 / Bundle ID 與正式包一致）
```

### 發行打包

依架構產生 ZIP、TAR.GZ 和 DMG，並驗證簽署、entitlements 與產物完整性（預設用固定自簽身分 **`StrokeMouse Release`**，便於輔助使用跨 Sparkle 更新保留）：

```bash
# 首次本機：./scripts/generate-codesign-cert.sh --import
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

發行與 CI secrets 說明見 `RELEASING.md` / `certs/README.md`。

版本發行使用 `./bump.sh -v x.y.z [-p]`；同版本重打 tag 並推送用 `./bump.sh -v x.y.z --force`。

### 測試

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## 使用說明

1. 啟動應用程式，選單列出現滑鼠圖示  
2. 授予 **輔助使用** 權限，並在選單列選擇「恢復手勢」/ 確認已啟用  
3. 開啟 **設定 → 手勢**，查看預設手勢或新增  
4. 選擇一種輸入方式：按住滑鼠觸發鍵繪製、按住單一修飾鍵進行觸控板繪製，或完成已設定的觸控手勢
5. 比對成功後執行綁定動作  

> **短按 vs 手勢**：觸發鍵的按下與放開由手勢引擎暫時擷取；未達到「最小滑動距離」便放開時會回放為正常點按，右鍵選單仍可用。所有滑鼠移動與拖曳事件都會直接交給系統更新游標，手勢引擎透過定時取樣記錄軌跡；前景 App 收不到配對的觸發鍵按下與放開，因此繪製時不會開啟或選取右鍵選單。左鍵和未設定為觸發鍵的滑鼠按鈕不受影響。

> **觸控板繪製**：修飾鍵監聽為 listen-only，不吞鍵盤事件；短路徑不會執行動作。軌跡來自系統指標位置，因此可以用觸控式軌跡板或滑鼠移動指標。StrokeMouse 不會阻止修飾鍵本身對目前 App 的影響。

> 快捷鍵會先啟動鎖定的應用程式；若鎖定了精確視窗，也會將該視窗提到最前，因此可能切換焦點或桌面空間。Finder 桌面等沒有一般視窗的位置仍可執行快捷鍵和「隱藏應用程式」；關閉、縮到最小、縮放、全螢幕、置中仍需要精確視窗。短按不會啟動目標。

預設手勢範例（均預設右鍵觸發；不同手勢可綁定不同按鍵）：

| 手勢 | 動作 |
|------|------|
| ↑ | Mission Control（⌃↑） |
| ↓ | 應用程式視窗（⌃↓） |
| ↓← | 縮到最小視窗 |
| ↓→ | 關閉視窗 |
| ↑→ | 開啟 Safari |
| →← | 播放 / 暫停 |
| ↑← | 開啟 GitHub |

## 設定檔

路徑：

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

日常可用 **設定 → 手勢** 多選後匯出 / 匯入 JSON 包。整庫可複製上述檔案備份或手動編輯（需保持結構合法）。設定頁可「在 Finder 中顯示」。

## 技術棧

- Swift / SwiftUI（macOS 14+）
- 輕量 MVVM + Service
- `CGEventTap` 全域滑鼠 / 修飾鍵事件
- `dlopen` / `dlsym` 動態載入 `MultitouchSupport`（實驗性觸控手勢，不靜態連結）
- JSON 設定持久化
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) 登入時啟動
- [Sparkle](https://github.com/sparkle-project/Sparkle) 簽署校驗與應用內更新
- XcodeGen 管理專案

## 授權與免責

本專案採用 [GNU Affero General Public License v3.0 (AGPL-3.0)](./LICENSE) 開源。

本機工具，全域事件與指令碼動作具有系統級能力。請僅新增你信任的 Shell / AppleScript。作者不對誤操作或權限濫用負責。
