---
title: "インストールとビルド"
description: "StrokeMouse のインストールまたはソースビルド。macOS 14+、CLI、Xcode、コード署名、テスト。"
keywords: "StrokeMouse インストール,ソースビルド,xcodebuild,コード署名,macOS 14"
---

# インストールとビルド

推奨のインストール方法は Homebrew です。[ダウンロードページ](/ja/download) から **Apple Silicon / Intel** の製品ビルドも入手できます。自分でコンパイルする場合は、下のソースビルドに従ってください。

## 要件

| 項目 | 要件 |
|------|-------------|
| OS | macOS 14 Sonoma 以降 |
| 開発ビルド | Xcode 16+ |
| プロジェクト生成 | [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`） |

## Homebrew（推奨）

[プロジェクト管理の Licoy Homebrew Tap](https://github.com/Licoy/homebrew-tap) からインストールします:

```bash
brew install --cask licoy/tap/strokemouse
```

StrokeMouse はアプリ内アップデートにも対応します。Homebrew にアップグレードを確認させてインストールさせるには:

```bash
brew upgrade --cask --greedy strokemouse
```

アンインストール時、設定はデフォルトで残ります。設定も消すには `--zap` を付けます:

```bash
brew uninstall --cask strokemouse
brew uninstall --cask --zap strokemouse
```

Homebrew と手動ダウンロードは同じリリースパッケージを使うため、初回起動の Gatekeeper とアクセシビリティの注意はどちらにも当てはまります。

## クローン

```bash
git clone https://github.com/Licoy/StrokeMouse.git
cd StrokeMouse
```

## 推奨: CLI ビルド

安定した出力パス `output/StrokeMouse.app` は、アクセシビリティの再承認を減らします。  
Debug は **StrokeMouse Dev**（Bundle ID `com.strokemouse.app.dev`）として表示され、製品版 **StrokeMouse** と並べて承認できます:

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app（アクセシビリティ: StrokeMouse Dev）
./scripts/build.sh --open    # 完了後に開く
./scripts/build.sh --release # Release（表示名 / Bundle ID は配布ビルドと同じ）
```

`project.yml` を変えたあと、またはソースを追加・削除したあと:

```bash
./scripts/generate_project.sh
```

## Xcode で実行

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

Scheme **StrokeMouse** → Run。

## コード署名

| 項目 | 値 |
|------|--------|
| Bundle ID | Release: `com.strokemouse.app`；Debug: `com.strokemouse.app.dev`（表示名 StrokeMouse Dev） |
| 開発 ID | キーチェーンの **`StrokeMouse Dev`**（自己署名。ローカルビルド用） |
| Release ID | **`StrokeMouse Release`** 自己署名 + Hardened Runtime（固定 ID。**ユーザーは証明書を入れない**） |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` または package（スモーク専用。**更新後にアクセシビリティは残らない**） |
| 公証 | 現在 Apple 公証 / Developer ID なし |

::: warning
GitHub Release の初回起動が Gatekeeper にブロックされたら、App を Control クリックして「開く」を選ぶか、システム設定 → プライバシーとセキュリティ → このまま開くを使ってください。

**アクセシビリティ**: 公式パッケージは固定の自己署名 ID を使うため、**同じ証明書で署名したアプリ内アップデートは通常許可を維持**します。古い ad-hoc ビルドからの移行や証明書のローテーションでは、**一度**再承認が必要です。エンドユーザーは発行者証明書を**インストールしません**。
:::

## リリース成果物

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

各アーキテクチャは ZIP、TAR.GZ、DMG を作ります。ZIP は Sparkle のアプリ内アップデートにも使います。バージョンとタグ付きリリースはリポジトリ直下の `RELEASING.md` を見てください。

## テスト

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## 依存関係

- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) — ログイン時に開く
- [Sparkle](https://github.com/sparkle-project/Sparkle) — アップデート署名とアプリ内インストール
- システム: `CGEventTap`、アクセシビリティ、任意の Apple Events

## 次へ

ビルドが成功したら [権限](./permissions) と [クイックスタート](./getting-started) に進んでください。
