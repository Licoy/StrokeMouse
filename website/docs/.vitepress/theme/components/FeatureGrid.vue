<script setup lang="ts">
import type { Component } from 'vue'
import {
  Menu,
  Sparkles,
  MousePointer2,
  AppWindow,
  Zap,
  Languages,
  type LucideIcon,
} from 'lucide-vue-next'

export interface FeatureItem {
  /** Lucide icon key registered in iconMap */
  icon: string
  title: string
  desc: string
}

const iconMap: Record<string, LucideIcon> = {
  menu: Menu,
  sparkles: Sparkles,
  mouse: MousePointer2,
  window: AppWindow,
  zap: Zap,
  languages: Languages,
}

defineProps<{
  heading?: string
  subheading?: string
  items: FeatureItem[]
}>()

function resolveIcon(name: string): Component {
  return iconMap[name] ?? Sparkles
}
</script>

<template>
  <section class="feature-grid">
    <header v-if="heading || subheading" class="feature-grid__header">
      <p v-if="subheading" class="feature-grid__kicker">{{ subheading }}</p>
      <h2 v-if="heading" class="feature-grid__heading">{{ heading }}</h2>
    </header>
    <div class="feature-grid__list">
      <article v-for="(item, i) in items" :key="i" class="feature-card">
        <div class="feature-card__icon-wrap" aria-hidden="true">
          <component :is="resolveIcon(item.icon)" class="feature-card__icon" :stroke-width="1.75" />
        </div>
        <h3 class="feature-card__title">{{ item.title }}</h3>
        <p class="feature-card__desc">{{ item.desc }}</p>
      </article>
    </div>
  </section>
</template>

<style scoped>
.feature-grid {
  margin: 3rem 0 2rem;
}

.feature-grid__header {
  margin-bottom: 1.5rem;
}

.feature-grid__kicker {
  margin: 0 0 0.4rem;
  font-family: var(--sm-font-mono);
  font-size: 12px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--sm-accent);
}

.feature-grid__heading {
  margin: 0;
  font-family: var(--sm-font-mono);
  font-size: 1.45rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--sm-text);
}

.feature-grid__list {
  display: grid;
  grid-template-columns: 1fr;
  gap: 1rem;
}

@media (min-width: 640px) {
  .feature-grid__list {
    grid-template-columns: repeat(2, 1fr);
  }
}

@media (min-width: 960px) {
  .feature-grid__list {
    grid-template-columns: repeat(3, 1fr);
  }
}

.feature-card {
  position: relative;
  padding: 1.3rem 1.25rem 1.4rem;
  border: none;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  box-shadow: inset 0 0 0 1px var(--sm-border);
  transition:
    box-shadow 0.18s ease,
    transform 0.18s ease;
}

.feature-card:hover {
  box-shadow:
    inset 0 0 0 1px var(--sm-border-strong),
    0 0 28px var(--sm-accent-glow);
  transform: translateY(-2px);
}

.feature-card__icon-wrap {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.5rem;
  height: 2.5rem;
  margin-bottom: 0.85rem;
  border-radius: 10px;
  background: var(--sm-accent-glow);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--sm-accent) 28%, transparent);
  color: var(--sm-accent);
}

.feature-card__icon {
  width: 1.25rem;
  height: 1.25rem;
}

.feature-card__title {
  margin: 0 0 0.45rem;
  font-family: var(--sm-font-mono);
  font-size: 0.95rem;
  font-weight: 600;
  color: var(--sm-text);
}

.feature-card__desc {
  margin: 0;
  font-size: 0.9rem;
  line-height: 1.55;
  color: var(--sm-text-muted);
}
</style>
