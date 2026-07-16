import type { DefaultTheme, LocaleSpecificConfig } from 'vitepress'
import { GITHUB_URL } from './shared'

export const zhConfig: LocaleSpecificConfig<DefaultTheme.Config> = {
  lang: 'zh-CN',
  title: 'StrokeMouse',
  description:
    'macOS 鼠标手势自定义工具 — 按住触发键绘制轨迹，匹配后执行快捷键、窗口操作与脚本。',
  themeConfig: {
    nav: [
      { text: '首页', link: '/' },
      { text: '下载', link: '/download' },
      {
        text: '文档',
        link: '/guide/getting-started',
        activeMatch: '/guide/',
      },
    ],
    sidebar: {
      '/guide/': [
        {
          text: '开始使用',
          items: [
            { text: '快速开始', link: '/guide/getting-started' },
            { text: '安装与构建', link: '/guide/installation' },
            { text: '权限说明', link: '/guide/permissions' },
          ],
        },
        {
          text: '操作手册',
          items: [
            { text: '手势系统', link: '/guide/gestures' },
            { text: '动作类型', link: '/guide/actions' },
            { text: '设置与菜单栏', link: '/guide/settings' },
            { text: '配置文件', link: '/guide/config-file' },
          ],
        },
        {
          text: '其他',
          items: [{ text: '常见问题 FAQ', link: '/guide/faq' }],
        },
      ],
    },
    editLink: {
      pattern: `${GITHUB_URL}/edit/main/website/docs/:path`,
      text: '在 GitHub 上编辑此页',
    },
    lastUpdated: {
      text: '最后更新',
    },
    outline: {
      label: '本页目录',
      level: [2, 3],
    },
    docFooter: {
      prev: '上一页',
      next: '下一页',
    },
    returnToTopLabel: '回到顶部',
    sidebarMenuLabel: '菜单',
    darkModeSwitchLabel: '主题',
    lightModeSwitchTitle: '切换到浅色',
    darkModeSwitchTitle: '切换到深色',
    footer: {
      message: '本地工具 · 全局事件与脚本具有系统级能力',
      copyright: 'StrokeMouse · 仅添加你信任的 Shell / AppleScript',
    },
  },
}
