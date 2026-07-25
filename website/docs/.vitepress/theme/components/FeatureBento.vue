<script setup lang="ts">
import { type Component, ref } from 'vue'
import {
  PhSquaresFour,
  PhPath,
  PhMouse,
  PhAppWindow,
  PhLightning,
  PhFolderSimple,
} from '@phosphor-icons/vue'
import { useReveal } from '../composables/useReveal'

export interface BentoItem {
  icon?: string
  title: string
  desc: string
  /** large | media | default */
  size?: 'large' | 'media' | 'default'
  image?: string
  imageAlt?: string
}

const iconMap: Record<string, Component> = {
  menu: PhSquaresFour,
  sparkles: PhPath,
  mouse: PhMouse,
  window: PhAppWindow,
  zap: PhLightning,
  import: PhFolderSimple,
}

defineProps<{
  heading: string
  lead?: string
  items: BentoItem[]
}>()

const root = ref<HTMLElement | null>(null)
useReveal(root)

function resolveIcon(name?: string): Component | null {
  if (!name) return null
  return iconMap[name] ?? PhPath
}
</script>

<template>
  <section ref="root" class="bento sm-section">
    <header class="bento__head sm-reveal">
      <h2 class="sm-section__title">{{ heading }}</h2>
      <p v-if="lead" class="sm-section__lead">{{ lead }}</p>
    </header>

    <div class="bento__grid">
      <article
        v-for="(item, i) in items"
        :key="i"
        class="bento__cell sm-reveal"
        :class="[
          item.size === 'large' ? 'bento__cell--large' : '',
          item.size === 'media' ? 'bento__cell--media' : '',
        ]"
        :style="{ transitionDelay: `${i * 50}ms` }"
      >
        <template v-if="item.size === 'media' && item.image">
          <div class="sm-bezel bento__bezel">
            <div class="sm-bezel__core bento__media-core">
              <img :src="item.image" :alt="item.imageAlt || item.title" loading="lazy" />
            </div>
          </div>
          <div class="bento__media-caption">
            <h3 class="bento__title">{{ item.title }}</h3>
            <p class="bento__desc">{{ item.desc }}</p>
          </div>
        </template>

        <template v-else-if="item.size === 'large'">
          <div class="bento__large-inner">
            <div v-if="item.image" class="bento__large-visual">
              <img :src="item.image" :alt="item.imageAlt || item.title" loading="lazy" />
            </div>
            <div class="bento__large-copy">
              <div v-if="item.icon" class="bento__icon" aria-hidden="true">
                <component :is="resolveIcon(item.icon)" :size="22" weight="light" />
              </div>
              <h3 class="bento__title">{{ item.title }}</h3>
              <p class="bento__desc">{{ item.desc }}</p>
            </div>
          </div>
        </template>

        <template v-else>
          <div v-if="item.icon" class="bento__icon" aria-hidden="true">
            <component :is="resolveIcon(item.icon)" :size="22" weight="light" />
          </div>
          <h3 class="bento__title">{{ item.title }}</h3>
          <p class="bento__desc">{{ item.desc }}</p>
        </template>
      </article>
    </div>
  </section>
</template>

<style scoped>
.bento__head {
  margin-bottom: 0.5rem;
}

.bento__grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 0.85rem;
}

@media (min-width: 768px) {
  .bento__grid {
    grid-template-columns: repeat(6, 1fr);
    grid-auto-rows: minmax(140px, auto);
    gap: 0.9rem;
  }

  .bento__cell {
    grid-column: span 2;
  }

  .bento__cell--large {
    grid-column: span 4;
    grid-row: span 2;
  }

  .bento__cell--media {
    grid-column: span 2;
    grid-row: span 2;
  }
}

.bento__cell {
  position: relative;
  padding: 1.25rem 1.2rem 1.35rem;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  box-shadow: inset 0 0 0 1px var(--sm-border);
  display: flex;
  flex-direction: column;
  transition:
    box-shadow 0.25s var(--sm-ease),
    transform 0.25s var(--sm-ease);
}

.bento__cell:hover {
  box-shadow: inset 0 0 0 1px var(--sm-border-strong);
  transform: translateY(-2px);
}

.bento__cell--large {
  padding: 0;
  overflow: hidden;
  background: var(--sm-bg-elevated);
}

.bento__cell--media {
  padding: 0;
  background: transparent;
  box-shadow: none;
}

.bento__cell--media:hover {
  transform: none;
  box-shadow: none;
}

.bento__large-inner {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 100%;
}

@media (min-width: 768px) {
  .bento__large-inner {
    flex-direction: row;
  }
}

.bento__large-visual {
  flex: 1.15;
  min-height: 180px;
  background: var(--sm-bg-soft);
  overflow: hidden;
}

.bento__large-visual img {
  width: 100%;
  height: 100%;
  object-fit: contain;
  object-position: center top;
  display: block;
  background: var(--sm-bg-soft);
}

.bento__large-copy {
  flex: 1;
  padding: 1.4rem 1.35rem;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.4rem;
}

.bento__bezel {
  height: auto;
}

.bento__media-core {
  aspect-ratio: 16 / 11;
  background: var(--sm-bg-soft);
}

.bento__media-core img {
  width: 100%;
  height: 100%;
  object-fit: contain;
  object-position: center top;
  display: block;
}

.bento__media-caption {
  padding: 0.9rem 0.15rem 0;
}

.bento__icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.4rem;
  height: 2.4rem;
  margin-bottom: 0.75rem;
  border-radius: 12px;
  background: var(--sm-accent-glow);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--sm-accent) 25%, transparent);
  color: var(--sm-accent);
}

.bento__title {
  margin: 0 0 0.35rem;
  font-family: var(--sm-font-sans);
  font-size: 1rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--sm-text);
}

.bento__desc {
  margin: 0;
  font-size: 0.9rem;
  line-height: 1.55;
  color: var(--sm-text-muted);
}
</style>
