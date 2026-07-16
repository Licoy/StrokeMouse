<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'
import {
  APP_VERSION,
  GITHUB_RELEASES,
  MAC_ASSETS,
  releaseAssetUrl,
} from '../constants'

const { lang } = useData()
const isZh = computed(() => !lang.value || lang.value.startsWith('zh'))

const copy = computed(() =>
  isZh.value
    ? {
        title: '下载 StrokeMouse',
        lead: 'macOS 生产构建。请按芯片架构选择对应安装包。',
        version: `v${APP_VERSION}`,
        recommended: '推荐下载',
        armTitle: 'Apple Silicon',
        armDesc: 'M1 / M2 / M3 / M4 及更新芯片',
        intelTitle: 'Intel',
        intelDesc: 'Intel 处理器 Mac',
        get: '下载',
        reqLabel: '系统要求',
        reqValue: 'macOS 14 Sonoma 或更高',
        installTitle: '安装说明',
        steps: [
          '下载对应架构的 .dmg 安装包',
          '打开 .dmg，将 StrokeMouse 拖入「应用程序」',
          '首次启动请右键点按 App 并选择「打开」，或在「隐私与安全性」中选择「仍要打开」',
          '首次启动后，在「系统设置 → 隐私与安全性 → 辅助功能」中授权',
          '打开设置 → 手势，开始配置',
        ],
        releases: '全部发行版',
        source: '从源码构建',
        sourceLink: '/guide/installation',
        note: '当前版本使用 ad-hoc 签名且未经 Apple 公证；若下载链接尚未可用，请按文档从源码构建。',
        fileLabel: '文件',
      }
    : {
        title: 'Download StrokeMouse',
        lead: 'Production builds for macOS. Pick the package that matches your chip.',
        version: `v${APP_VERSION}`,
        recommended: 'Recommended',
        armTitle: 'Apple Silicon',
        armDesc: 'M1 / M2 / M3 / M4 and later',
        intelTitle: 'Intel',
        intelDesc: 'Intel-based Mac',
        get: 'Download',
        reqLabel: 'Requirements',
        reqValue: 'macOS 14 Sonoma or later',
        installTitle: 'Installation',
        steps: [
          'Download the .dmg for your architecture',
          'Open the .dmg and drag StrokeMouse into Applications',
          'For first launch, right-click the app and choose Open, or use Privacy & Security → Open Anyway',
          'On first launch, grant Accessibility in System Settings → Privacy & Security',
          'Open Settings → Gestures and start configuring',
        ],
        releases: 'All releases',
        source: 'Build from source',
        sourceLink: '/en/guide/installation',
        note: 'Current releases are ad-hoc signed and not notarized. If downloads are not live yet, build from source.',
        fileLabel: 'File',
      },
)

const cards = computed(() => [
  {
    id: 'arm64' as const,
    title: copy.value.armTitle,
    desc: copy.value.armDesc,
    file: MAC_ASSETS.arm64.file,
    href: releaseAssetUrl(MAC_ASSETS.arm64.file),
    badge: 'M',
  },
  {
    id: 'x64' as const,
    title: copy.value.intelTitle,
    desc: copy.value.intelDesc,
    file: MAC_ASSETS.x64.file,
    href: releaseAssetUrl(MAC_ASSETS.x64.file),
    badge: 'Intel',
  },
])
</script>

<template>
  <div class="sm-download">
    <div class="sm-download__wrap">
      <header class="sm-download__hero">
        <h1>{{ copy.title }}</h1>
        <p class="sm-download__lead">{{ copy.lead }}</p>
        <div class="sm-download__meta">
          <a class="sm-download__ver" :href="GITHUB_RELEASES" target="_blank" rel="noopener">
            {{ copy.version }}
          </a>
          <span class="sm-download__plat">macOS</span>
        </div>
      </header>

      <section class="sm-download__section">
        <h2 class="sm-download__h2">{{ copy.recommended }}</h2>
        <div class="sm-download__grid">
          <a
            v-for="card in cards"
            :key="card.id"
            class="sm-download__card"
            :href="card.href"
          >
            <div class="sm-download__card-top">
              <span class="sm-download__chip">{{ card.badge }}</span>
              <div>
                <div class="sm-download__card-title">{{ card.title }}</div>
                <div class="sm-download__card-desc">{{ card.desc }}</div>
              </div>
            </div>
            <code class="sm-download__file">{{ card.file }}</code>
            <span class="sm-download__action">
              <span class="sm-download__action-icon" aria-hidden="true">↓</span>
              {{ copy.get }}
            </span>
          </a>
        </div>
      </section>

      <div class="sm-download__info">
        <div class="sm-download__req">
          <span class="sm-download__req-k">{{ copy.reqLabel }}</span>
          <span class="sm-download__req-v">{{ copy.reqValue }}</span>
        </div>
        <div class="sm-download__links">
          <a :href="GITHUB_RELEASES" target="_blank" rel="noopener">{{ copy.releases }} →</a>
          <a :href="copy.sourceLink">{{ copy.source }} →</a>
        </div>
      </div>

      <p class="sm-download__note">{{ copy.note }}</p>

      <section class="sm-download__section">
        <h2 class="sm-download__h2">{{ copy.installTitle }}</h2>
        <ol class="sm-download__steps">
          <li v-for="(step, i) in copy.steps" :key="i">{{ step }}</li>
        </ol>
      </section>
    </div>
  </div>
</template>

<style scoped>
.sm-download {
  position: relative;
  padding: calc(var(--vp-nav-height, 64px) + 48px) 1.25rem 72px;
  min-height: 70vh;
}

.sm-download::before {
  content: '';
  pointer-events: none;
  position: absolute;
  left: 50%;
  top: 0;
  transform: translateX(-50%);
  width: min(720px, 90vw);
  height: 240px;
  background: radial-gradient(ellipse at center, var(--sm-accent-glow), transparent 70%);
  z-index: 0;
}

.sm-download__wrap {
  position: relative;
  z-index: 1;
  max-width: 760px;
  margin: 0 auto;
}

.sm-download__hero {
  text-align: center;
  margin-bottom: 2.5rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.85rem;
}

.sm-download__hero h1 {
  margin: 0;
  font-family: var(--sm-font-mono);
  font-size: clamp(2rem, 5vw, 2.75rem);
  font-weight: 800;
  letter-spacing: -0.03em;
  color: var(--sm-text);
}

.sm-download__lead {
  margin: 0;
  max-width: 32em;
  color: var(--sm-text-muted);
  font-size: 1.05rem;
  line-height: 1.65;
}

.sm-download__meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
  align-items: center;
  justify-content: center;
  margin-top: 0.25rem;
}

.sm-download__ver,
.sm-download__plat {
  display: inline-flex;
  align-items: center;
  font-family: var(--sm-font-mono);
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.04em;
  padding: 0.35rem 0.75rem;
  border-radius: 999px;
  text-decoration: none;
}

.sm-download__ver {
  color: var(--sm-accent);
  background: var(--sm-accent-glow);
  box-shadow: inset 0 0 0 1px var(--sm-border-strong);
}

.sm-download__ver:hover {
  box-shadow: inset 0 0 0 1px var(--sm-accent);
}

.sm-download__plat {
  color: var(--sm-text-muted);
  background: var(--sm-chrome);
  box-shadow: inset 0 0 0 1px var(--sm-border);
}

.sm-download__section {
  margin-bottom: 2rem;
}

.sm-download__h2 {
  margin: 0 0 1rem;
  font-family: var(--sm-font-mono);
  font-size: 0.8rem;
  font-weight: 650;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--sm-text-faint);
}

.sm-download__grid {
  display: grid;
  gap: 0.85rem;
}

@media (min-width: 640px) {
  .sm-download__grid {
    grid-template-columns: 1fr 1fr;
  }
}

.sm-download__card {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
  padding: 1.15rem 1.2rem 1.2rem;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  box-shadow: inset 0 0 0 1px var(--sm-border);
  text-decoration: none !important;
  color: inherit;
  transition:
    box-shadow 0.18s ease,
    transform 0.15s ease,
    background 0.15s ease;
}

.sm-download__card:hover {
  box-shadow: inset 0 0 0 1px var(--sm-border-strong), 0 12px 32px rgba(0, 0, 0, 0.18);
  transform: translateY(-2px);
  background: color-mix(in srgb, var(--sm-panel) 90%, var(--sm-accent-glow));
}

.sm-download__card-top {
  display: flex;
  gap: 0.75rem;
  align-items: flex-start;
}

.sm-download__chip {
  flex-shrink: 0;
  min-width: 2.4rem;
  height: 2.4rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 10px;
  font-family: var(--sm-font-mono);
  font-size: 11px;
  font-weight: 700;
  color: var(--sm-accent);
  background: var(--sm-accent-glow);
  box-shadow: inset 0 0 0 1px var(--sm-border-strong);
}

.sm-download__card-title {
  font-family: var(--sm-font-mono);
  font-weight: 700;
  font-size: 1rem;
  color: var(--sm-text);
  letter-spacing: -0.02em;
}

.sm-download__card-desc {
  margin-top: 0.2rem;
  font-size: 0.85rem;
  color: var(--sm-text-muted);
  line-height: 1.4;
}

.sm-download__file {
  font-family: var(--sm-font-mono);
  font-size: 11px;
  color: var(--sm-text-faint);
  background: var(--sm-chrome);
  padding: 0.35rem 0.55rem;
  border-radius: 6px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sm-download__action {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  margin-top: auto;
  padding: 0.55rem 0.85rem;
  border-radius: 8px;
  font-family: var(--sm-font-mono);
  font-size: 13px;
  font-weight: 650;
  color: #04140c;
  background: var(--sm-accent);
}

.dark .sm-download__action {
  color: #04140c;
}

html:not(.dark) .sm-download__action {
  color: #ffffff;
}

.sm-download__action-icon {
  font-size: 14px;
  line-height: 1;
}

.sm-download__info {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin: 0.5rem 0 1rem;
  padding: 1rem 1.1rem;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  box-shadow: inset 0 0 0 1px var(--sm-border);
}

.sm-download__req {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
}

.sm-download__req-k {
  font-family: var(--sm-font-mono);
  font-size: 11px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--sm-text-faint);
}

.sm-download__req-v {
  font-size: 0.92rem;
  color: var(--sm-text);
}

.sm-download__links {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem 1.25rem;
}

.sm-download__links a {
  font-family: var(--sm-font-mono);
  font-size: 13px;
  color: var(--sm-accent);
  text-decoration: none;
}

.sm-download__links a:hover {
  text-decoration: underline;
}

.sm-download__note {
  margin: 0 0 2rem;
  font-size: 0.85rem;
  line-height: 1.55;
  color: var(--sm-text-faint);
}

.sm-download__steps {
  margin: 0;
  padding: 1.15rem 1.15rem 1.15rem 2.1rem;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  box-shadow: inset 0 0 0 1px var(--sm-border);
  color: var(--sm-text-muted);
  line-height: 1.7;
}

.sm-download__steps li {
  margin: 0.35rem 0;
}

.sm-download__steps li::marker {
  color: var(--sm-accent);
  font-weight: 700;
}
</style>
