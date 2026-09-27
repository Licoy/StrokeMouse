# StrokeMouse Website

产品官网与操作手册，基于 [VitePress](https://vitepress.dev/)。

语言与 README 对齐，共 7 种；语言切换器显示该语言自己的名称。首次打开未带语言前缀的地址（`/`、`/guide/...`、`/download`）时，按浏览器语言跳到对应译本；无法识别则回落到 English。手动切换或打开 `/en/` 等带前缀链接后会记住选择，搜索引擎爬虫不跳转。

| 语言 | 路径 |
|------|------|
| 简体中文 | `/` |
| English | `/en/` |
| 繁體中文 | `/zh-hant/` |
| 한국어 | `/ko/` |
| 日本語 | `/ja/` |
| Русский | `/ru/` |
| Français | `/fr/` |

主题：扩展 VitePress 默认主题的产品向定制（Geist + 品牌蓝，`docs/.vitepress/theme`）。

## 开发

需要 Node.js 18+。

```bash
cd website
npm install
npm run dev
```

浏览器打开 `http://localhost:9243`（端口已固定为 9243）。

## 构建与预览

```bash
npm run build    # 输出到 docs/.vitepress/dist
npm run preview  # 预览生产构建
```

## 目录

```text
docs/
  .vitepress/     # 配置 + 主题 + 组件
  guide/          # 简体中文文档（站点根路径）
  en/             # English
  zh-hant/        # 繁體中文
  ko/             # 한국어
  ja/             # 日本語
  ru/             # Русский
  fr/             # Français
  public/         # logo / favicon / screenshots / video
    screenshots/  # 产品截图唯一源（README 与官网共用）
    video/        # 宣传片（网页压缩版）、官网海报、README 缩略图
  index.md        # 简体中文首页
```

修改语言列表：`docs/.vitepress/config/locales.ts`。  
修改导航 / 侧栏 / 搜索文案：`docs/.vitepress/config/chrome.ts`。  
修改主题组件文案：`docs/.vitepress/theme/i18n.ts`。  
修改全站视觉：`docs/.vitepress/theme/style.css` 与 `components/`。

**宣传片**：`docs/public/video/` 下是宣传片的网页压缩版、海报与 README 缩略图，官网首页用 `PromoVideo` 组件播放；GitHub 不能在 README 中内嵌仓库里的视频，所以各语言 README 放的是缩略图，链接到官网上的视频文件。

**截图单源**：`docs/public/screenshots/` 为仓库内唯一产品截图目录。官网首页幻灯片使用 `/screenshots/*.png`；根目录 `README.md` 与各语言 README 引用 `website/docs/public/screenshots/`。

## 与 App 仓库的关系

本目录独立于 Xcode / Swift 工程，不参与 `xcodebuild`。品牌资源来自仓库 `design/logo/`。

## 许可

与主仓库一致，采用 [AGPL-3.0](../LICENSE)。
