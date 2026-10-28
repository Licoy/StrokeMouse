# StrokeMouse Website

产品官网与操作手册：Python 脚本在构建时把 Markdown 文档和 Jinja2 模板渲染成纯静态 HTML，不依赖前端框架，GitHub Actions 构建后部署到 GitHub Pages。

语言与 README 对齐，共 7 种；语言切换器显示该语言自己的名称。首次打开未带语言前缀的地址（`/`、`/guide/...`、`/download`）时，按浏览器语言跳到对应译本，无法识别则回落到 English；手动切换或打开 `/en/` 等带前缀链接后会记住选择，搜索引擎与 AI 爬虫不跳转。

| 语言 | 路径 | 内容目录 |
|------|------|----------|
| 简体中文 | `/` | `content/zh-hans/` |
| English | `/en/` | `content/en/` |
| 繁體中文 | `/zh-hant/` | `content/zh-hant/` |
| 한국어 | `/ko/` | `content/ko/` |
| 日本語 | `/ja/` | `content/ja/` |
| Русский | `/ru/` | `content/ru/` |
| Français | `/fr/` | `content/fr/` |

## 开发

需要 Python 3.11+。

```bash
cd website
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

.venv/bin/python build.py --serve          # http://localhost:9243，改动后自动重建
.venv/bin/python build.py --serve --offline  # 不请求 GitHub Releases
```

## 构建

```bash
.venv/bin/python build.py            # 输出到 dist/
.venv/bin/python build.py --out /tmp/site --offline
```

构建时会：

- 读取 `../project.yml` 的 `MARKETING_VERSION`，并请求 GitHub Releases（可选 `GITHUB_TOKEN`，失败时不中断）；最新 Release 的版本号优先，下载页与更新日志页用 Release 数据，不再需要 `bump.sh` 同步网站版本；
- 用 `git log` 取每篇文档的最后修改日期，写入页面与 `sitemap.xml`（CI 需 `fetch-depth: 0`）；
- 给 CSS / JS 加内容哈希 `?v=`，生成 `sitemap.xml`、`robots.txt`、`llms.txt`、`llms-full.txt`、`changelog.xml`（Atom）、每篇文档的 `.md` 原文、各语言搜索索引 `search/<code>.json` 与 `404.html`。

GitHub Pages 使用无扩展名地址：`/guide/faq` 对应 `guide/faq.html`；本地 `--serve` 模拟同样的规则。

## 目录

```text
build.py              # 入口：渲染全部页面，--serve 开发服务器
requirements.txt
sitegen/
  config.py           # 站点常量、语言表、文档分组、页面 ID
  docs.py             # Markdown → HTML（提示块、组件占位、目录、FAQ 抽取）
  seo.py              # JSON-LD、sitemap、robots、llms.txt、Atom
content/
  <code>/site.toml    # 该语言的界面文案；缺失的键回落到 en/site.toml
  <code>/guide/*.md   # 该语言的文档
templates/            # Jinja2 页面与 partials
static/
  assets/             # site.css、site.js、pad.js（首页试画板）
  fonts/              # 自托管 Source Serif 4 / JetBrains Mono
  img/                # 图标、OG 图
  screenshots/        # 产品截图唯一源（README 与官网共用）
  video/              # 宣传片网页压缩版、海报、README 缩略图
```

**文案**：界面文案只写在 `content/<code>/site.toml`；`{⌘}` 这类花括号会渲染成键帽，`[文字](guide/faq)` 会渲染成当前语言下的站内链接。新增键时先写 `en/site.toml`，再补其余 6 种语言。

**文档**：`content/<code>/guide/*.md` 支持 frontmatter（`title`、`description`、`keywords`）、`::: tip|warning|danger 标题` 提示块、`{#id}` 自定义锚点与 `<DefaultGestures />` 组件。新增文档页时还要在 `sitegen/config.py` 的 `GUIDE_GROUPS` 里登记。

**新增语言**：在 `sitegen/config.py` 的 `LOCALES` 中加一项，建 `content/<code>/site.toml` 与 `guide/`，并在 `static/assets/site.css` 里按需补 `:lang()` 字体栈。

**字体**：正文默认衬线；拉丁字母与西里尔字母用自托管的 Source Serif 4，中文用宋体（Songti SC / 思源宋体 / SimSun），繁中用宋体 TC / 新细明体，日文用明朝，韩文用明朝体（AppleMyungjo / Nanum Myeongjo）。CJK 页面里 Source Serif 只覆盖基本拉丁与 Latin-1，标点保持全角。

**宣传片**：GitHub 不能在 README 中内嵌仓库里的视频，各语言 README 放缩略图并链接到官网上的视频文件。更换视频后，要同步更新 `build.py` 的 `PROMO_VIDEO` 和各 README 链接里的 `?v=`（取文件 SHA-256 的前 8 位）；站点前面有 CDN 缓存，URL 不变的话访客会继续拿到旧文件。

**截图单源**：`static/screenshots/` 为仓库内唯一产品截图目录。README 引用其中的 PNG；官网优先用同名 WebP（`cwebp -q 82 N.png -o N.webp` 生成），更换截图时两者都要更新，尺寸变化时同步 `build.py` 的 `SCREENSHOTS`。

## 与 App 仓库的关系

本目录独立于 Xcode / Swift 工程，不参与 `xcodebuild`。品牌资源来自仓库 `design/logo/`。

## 许可

与主仓库一致，采用 [AGPL-3.0](../LICENSE)。
