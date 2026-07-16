import { defineConfig } from 'vitepress'
import { sharedConfig } from './config/shared'
import { zhConfig } from './config/zh'
import { enConfig } from './config/en'

export default defineConfig({
  ...sharedConfig,
  locales: {
    root: {
      label: '简体中文',
      lang: 'zh-CN',
      ...zhConfig,
    },
    en: {
      label: 'English',
      lang: 'en-US',
      ...enConfig,
    },
  },
  vite: {
    server: {
      port: 9243,
      strictPort: true,
    },
    preview: {
      port: 9243,
      strictPort: true,
    },
  },
})
