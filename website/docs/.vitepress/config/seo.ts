/**
 * Per-page SEO metadata for StrokeMouse site (zh + en).
 * Used by transformPageData + transformHead at build time.
 */

// Keep in sync with shared.ts SITE_URL / SITE_TITLE (avoid circular imports)
export const SITE_TITLE = 'StrokeMouse'
export const SITE_URL = 'https://strokemouse.app'

export interface PageSeo {
  /** Document title (without site suffix) */
  title: string
  /** Meta description ~70–160 chars */
  description: string
  /** Comma-separated keywords */
  keywords: string
  /** Open Graph type */
  ogType?: 'website' | 'article'
}

/** relativePath → SEO (VitePress style, e.g. guide/getting-started.md) */
export const PAGE_SEO: Record<string, PageSeo> = {
  // ——— Chinese (root) ———
  'index.md': {
    title: 'StrokeMouse',
    description:
      'StrokeMouse 是 macOS 鼠标手势自定义工具。按住触发键绘制轨迹，匹配后执行快捷键、打开应用、窗口操作、媒体键与脚本。支持 Apple Silicon 与 Intel。',
    keywords:
      'StrokeMouse,macOS 鼠标手势,鼠标手势,快捷键,Mission Control,辅助功能,CGEventTap,手势软件',
    ogType: 'website',
  },
  'download.md': {
    title: '下载',
    description:
      '下载 StrokeMouse for macOS。提供 Apple Silicon（M 系列）与 Intel 安装包，macOS 14 及以上。免费本地鼠标手势工具。',
    keywords: 'StrokeMouse 下载,macOS 下载,Apple Silicon,Intel,dmg,鼠标手势软件下载',
    ogType: 'website',
  },
  'guide/getting-started.md': {
    title: '快速开始',
    description:
      'StrokeMouse 快速开始：安装后授权辅助功能、启用手势、按住右键画出第一笔轨迹。三分钟上手 macOS 鼠标手势。',
    keywords: 'StrokeMouse 教程,快速开始,鼠标手势入门,辅助功能授权',
    ogType: 'article',
  },
  'guide/installation.md': {
    title: '安装与构建',
    description:
      'StrokeMouse 安装与源码构建说明：系统要求 macOS 14+、命令行构建、Xcode 运行、签名与测试。',
    keywords: 'StrokeMouse 安装,源码构建,xcodebuild,签名,macOS 14',
    ogType: 'article',
  },
  'guide/permissions.md': {
    title: '权限说明',
    description:
      'StrokeMouse 权限说明：辅助功能（Accessibility）用于全局鼠标监听，自动化（Automation）用于 AppleScript。授权失败排查指南。',
    keywords: 'StrokeMouse 权限,辅助功能,Accessibility,Automation,AppleScript',
    ogType: 'article',
  },
  'guide/gestures.md': {
    title: '手势系统',
    description:
      'StrokeMouse 手势系统：触发键、短按回放、自由轨迹匹配、App 作用域与默认手势示例。学习如何稳定自定义鼠标手势。',
    keywords: '鼠标手势,触发键,freePath,轨迹匹配,App 作用域,默认手势',
    ogType: 'article',
  },
  'guide/actions.md': {
    title: '动作类型',
    description:
      'StrokeMouse 支持的动作：快捷键、打开 App、URL、媒体键、窗口操作、Shell 与 AppleScript。了解如何绑定手势到动作。',
    keywords: '手势动作,快捷键,Shell,AppleScript,窗口操作,媒体键',
    ogType: 'article',
  },
  'guide/settings.md': {
    title: '设置与菜单栏',
    description:
      'StrokeMouse 设置与菜单栏：启停手势、手势列表、编辑器、主题、登录启动与权限入口说明。',
    keywords: 'StrokeMouse 设置,菜单栏,登录启动,手势编辑器,主题',
    ogType: 'article',
  },
  'guide/config-file.md': {
    title: '配置文件',
    description:
      'StrokeMouse 配置文件路径与备份：~/Library/Application Support/StrokeMouse/gestures.json。JSON 结构说明与迁移建议。',
    keywords: 'gestures.json,配置备份,Application Support,StrokeMouse 配置',
    ogType: 'article',
  },
  'guide/faq.md': {
    title: '常见问题 FAQ',
    description:
      'StrokeMouse 常见问题：手势无反应、右键菜单、误触发、权限、登录启动、配置备份与鼠标要求等解答。',
    keywords: 'StrokeMouse FAQ,手势不工作,右键菜单,故障排除',
    ogType: 'article',
  },

  // ——— English ———
  'en/index.md': {
    title: 'StrokeMouse',
    description:
      'StrokeMouse is a macOS mouse gesture tool. Hold a trigger button, draw a stroke, and run shortcuts, apps, window actions, media keys, or scripts. Apple Silicon and Intel builds.',
    keywords:
      'StrokeMouse,macOS mouse gestures,mouse gestures,shortcuts,Mission Control,Accessibility,CGEventTap',
    ogType: 'website',
  },
  'en/download.md': {
    title: 'Download',
    description:
      'Download StrokeMouse for macOS. Apple Silicon (M-series) and Intel installers. Requires macOS 14+. Free local mouse gesture utility.',
    keywords: 'StrokeMouse download,macOS download,Apple Silicon,Intel,dmg,mouse gesture app',
    ogType: 'website',
  },
  'en/guide/getting-started.md': {
    title: 'Quick start',
    description:
      'Get started with StrokeMouse: grant Accessibility, enable gestures, and draw your first stroke with the right button in minutes.',
    keywords: 'StrokeMouse tutorial,quick start,mouse gestures,Accessibility',
    ogType: 'article',
  },
  'en/guide/installation.md': {
    title: 'Install & build',
    description:
      'Install StrokeMouse or build from source. macOS 14+, CLI build, Xcode, code signing, and tests.',
    keywords: 'StrokeMouse install,build from source,xcodebuild,code signing,macOS 14',
    ogType: 'article',
  },
  'en/guide/permissions.md': {
    title: 'Permissions',
    description:
      'StrokeMouse permissions: Accessibility for global mouse listening, Automation for AppleScript. Troubleshooting failed authorization.',
    keywords: 'StrokeMouse permissions,Accessibility,Automation,AppleScript,macOS privacy',
    ogType: 'article',
  },
  'en/guide/gestures.md': {
    title: 'Gestures',
    description:
      'StrokeMouse gesture system: triggers, short-click replay, free-path matching, app scope, and default gesture examples.',
    keywords: 'mouse gestures,trigger button,free-path matching,app scope,default gestures',
    ogType: 'article',
  },
  'en/guide/actions.md': {
    title: 'Actions',
    description:
      'StrokeMouse actions: shortcuts, open app, URL, media keys, window commands, Shell, and AppleScript.',
    keywords: 'gesture actions,shortcuts,Shell,AppleScript,window actions,media keys',
    ogType: 'article',
  },
  'en/guide/settings.md': {
    title: 'Settings & menu bar',
    description:
      'StrokeMouse settings and menu bar: start/stop gestures, gesture list, editor, appearance, launch at login, and permissions.',
    keywords: 'StrokeMouse settings,menu bar,launch at login,gesture editor,theme',
    ogType: 'article',
  },
  'en/guide/config-file.md': {
    title: 'Config file',
    description:
      'StrokeMouse config path and backup: ~/Library/Application Support/StrokeMouse/gestures.json. Structure and migration tips.',
    keywords: 'gestures.json,config backup,Application Support,StrokeMouse config',
    ogType: 'article',
  },
  'en/guide/faq.md': {
    title: 'FAQ',
    description:
      'StrokeMouse FAQ: gestures not working, right-click menu, false matches, permissions, login items, backups, and mouse requirements.',
    keywords: 'StrokeMouse FAQ,troubleshooting,right-click menu,permissions',
    ogType: 'article',
  },
}

const FALLBACK_ZH: PageSeo = {
  title: SITE_TITLE,
  description:
    'StrokeMouse — macOS 鼠标手势自定义工具。按住触发键绘制轨迹，匹配后执行动作。',
  keywords: 'StrokeMouse,macOS,鼠标手势',
  ogType: 'website',
}

const FALLBACK_EN: PageSeo = {
  title: SITE_TITLE,
  description:
    'StrokeMouse — custom mouse gestures for macOS. Hold a trigger, draw a stroke, run actions.',
  keywords: 'StrokeMouse,macOS,mouse gestures',
  ogType: 'website',
}

export function resolvePageSeo(relativePath: string): PageSeo {
  const key = relativePath.replace(/\\/g, '/')
  if (PAGE_SEO[key]) return PAGE_SEO[key]
  const isEn = key.startsWith('en/')
  return isEn ? FALLBACK_EN : FALLBACK_ZH
}

/** Convert relativePath to site pathname (cleanUrls) */
export function pathFromRelative(relativePath: string): string {
  let p = relativePath.replace(/\\/g, '/').replace(/\.md$/i, '')
  if (p.endsWith('/index')) p = p.slice(0, -'/index'.length)
  if (p === 'index' || p === '') return '/'
  return p.startsWith('/') ? p : `/${p}`
}

/** Alternate locale path for hreflang */
export function alternatePath(pathname: string): { zh: string; en: string } {
  const clean = pathname === '' ? '/' : pathname
  if (clean === '/') return { zh: '/', en: '/en/' }
  if (clean === '/en' || clean === '/en/') return { zh: '/', en: '/en/' }
  if (clean.startsWith('/en/') || clean === '/en') {
    const rest = clean.replace(/^\/en/, '') || '/'
    return { zh: rest === '' ? '/' : rest, en: clean.endsWith('/') ? clean : `${clean}` }
  }
  // zh path
  const en = clean === '/' ? '/en/' : `/en${clean.startsWith('/') ? clean : `/${clean}`}`
  return { zh: clean, en }
}

export function absoluteUrl(pathname: string): string {
  if (pathname === '/') return `${SITE_URL}/`
  const p = pathname.startsWith('/') ? pathname : `/${pathname}`
  return `${SITE_URL}${p}`
}

export const DEFAULT_OG_IMAGE = `${SITE_URL}/app-icon.png`
export const SITE_NAME = SITE_TITLE
