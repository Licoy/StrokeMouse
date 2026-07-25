<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'
import { GITHUB_REPO } from '../constants'

const { lang } = useData()

const isZh = computed(() => !lang.value || lang.value.startsWith('zh'))

const copy = computed(() =>
  isZh.value
    ? {
        brand: 'StrokeMouse',
        docs: '文档',
        docsLink: '/guide/getting-started',
        download: '下载',
        downloadLink: '/download',
        install: '源码构建',
        installLink: '/guide/installation',
        github: '源码',
        license: 'AGPL-3.0',
      }
    : {
        brand: 'StrokeMouse',
        docs: 'Docs',
        docsLink: '/en/guide/getting-started',
        download: 'Download',
        downloadLink: '/en/download',
        install: 'Build from source',
        installLink: '/en/guide/installation',
        github: 'Source',
        license: 'AGPL-3.0',
      },
)

const licenseUrl = `${GITHUB_REPO}/blob/main/LICENSE`
</script>

<template>
  <footer class="sm-footer">
    <div class="sm-footer__inner">
      <div class="sm-footer__top">
        <div class="sm-footer__brand">
          <img class="sm-footer__logo" src="/logo.svg" width="22" height="22" alt="" />
          <span class="sm-footer__name">{{ copy.brand }}</span>
        </div>
        <nav class="sm-footer__nav">
          <a :href="copy.downloadLink">{{ copy.download }}</a>
          <a :href="copy.docsLink">{{ copy.docs }}</a>
          <a :href="copy.installLink">{{ copy.install }}</a>
          <a :href="GITHUB_REPO" target="_blank" rel="noreferrer">
            {{ copy.github }}
          </a>
          <a :href="licenseUrl" target="_blank" rel="noreferrer">
            {{ copy.license }}
          </a>
        </nav>
      </div>
    </div>
  </footer>
</template>

<style scoped>
.sm-footer {
  margin-top: 2rem;
  border-top: 1px solid var(--sm-border);
  background: color-mix(in srgb, var(--sm-bg-elevated) 88%, transparent);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
}

.sm-footer__inner {
  max-width: 1200px;
  margin: 0 auto;
  padding: 2.25rem 1.5rem 2.5rem;
}

.sm-footer__top {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 1.25rem 2rem;
}

.sm-footer__brand {
  display: flex;
  align-items: center;
  gap: 0.55rem;
}

.sm-footer__logo {
  display: block;
  width: 22px;
  height: 22px;
}

.sm-footer__name {
  font-family: var(--sm-font-sans);
  font-weight: 600;
  font-size: 0.95rem;
  color: var(--sm-text);
  letter-spacing: -0.02em;
}

.sm-footer__nav {
  display: flex;
  flex-wrap: wrap;
  gap: 0.85rem 1.35rem;
}

.sm-footer__nav a {
  font-family: var(--sm-font-sans);
  font-size: 0.875rem;
  font-weight: 500;
  color: var(--sm-text-muted);
  text-decoration: none;
  padding: 0.2rem 0;
  transition: color 0.2s var(--sm-ease);
}

.sm-footer__nav a:hover {
  color: var(--sm-accent);
}

@media (prefers-reduced-transparency: reduce) {
  .sm-footer {
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
    background: var(--sm-bg-elevated);
  }
}
</style>
