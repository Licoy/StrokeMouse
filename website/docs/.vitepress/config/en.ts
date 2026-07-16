import type { DefaultTheme, LocaleSpecificConfig } from 'vitepress'
import { GITHUB_URL } from './shared'

export const enConfig: LocaleSpecificConfig<DefaultTheme.Config> = {
  lang: 'en-US',
  title: 'StrokeMouse',
  description:
    'Custom mouse gestures for macOS — hold a trigger button, draw a stroke, run shortcuts, window actions, and scripts.',
  themeConfig: {
    nav: [
      { text: 'Home', link: '/en/' },
      { text: 'Download', link: '/en/download' },
      {
        text: 'Docs',
        link: '/en/guide/getting-started',
        activeMatch: '/en/guide/',
      },
    ],
    sidebar: {
      '/en/guide/': [
        {
          text: 'Get started',
          items: [
            { text: 'Quick start', link: '/en/guide/getting-started' },
            { text: 'Install & build', link: '/en/guide/installation' },
            { text: 'Permissions', link: '/en/guide/permissions' },
          ],
        },
        {
          text: 'Manual',
          items: [
            { text: 'Gestures', link: '/en/guide/gestures' },
            { text: 'Actions', link: '/en/guide/actions' },
            { text: 'Settings & menu bar', link: '/en/guide/settings' },
            { text: 'Config file', link: '/en/guide/config-file' },
          ],
        },
        {
          text: 'Other',
          items: [{ text: 'FAQ', link: '/en/guide/faq' }],
        },
      ],
    },
    editLink: {
      pattern: `${GITHUB_URL}/edit/main/website/docs/:path`,
      text: 'Edit this page on GitHub',
    },
    lastUpdated: {
      text: 'Last updated',
    },
    outline: {
      label: 'On this page',
      level: [2, 3],
    },
    docFooter: {
      prev: 'Previous',
      next: 'Next',
    },
    returnToTopLabel: 'Back to top',
    sidebarMenuLabel: 'Menu',
    darkModeSwitchLabel: 'Theme',
    lightModeSwitchTitle: 'Switch to light',
    darkModeSwitchTitle: 'Switch to dark',
    footer: {
      message: 'Local tool · Global events and scripts have system-level power',
      copyright: 'StrokeMouse · Only add Shell / AppleScript you trust',
    },
  },
}
