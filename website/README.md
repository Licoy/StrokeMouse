# StrokeMouse Website

产品官网与操作手册，基于 [VitePress](https://vitepress.dev/)。

- 默认语言：简体中文（`/`）
- 英文：`/en/`
- 主题：扩展 VitePress 默认主题的极客风定制（`docs/.vitepress/theme`）

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
  guide/          # 中文文档
  en/             # 英文首页与文档
  public/         # logo / favicon
  index.md        # 中文首页
```

修改导航 / 侧栏：`docs/.vitepress/config/zh.ts`、`en.ts`。  
修改全站视觉：`docs/.vitepress/theme/style.css` 与 `components/`。

## 与 App 仓库的关系

本目录独立于 Xcode / Swift 工程，不参与 `xcodebuild`。品牌资源来自仓库 `design/logo/`。
