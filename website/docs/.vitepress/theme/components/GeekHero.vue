<script setup lang="ts">
import HeroStrokeHud from './HeroStrokeHud.vue'

defineProps<{
  badge?: string
  title: string
  titleAccent?: string
  tagline: string
  primaryText: string
  primaryLink: string
  secondaryText: string
  secondaryLink: string
  statusLine?: string
  hudLabel?: string
  hudFooterLeft?: string
  hudFooterRight?: string
}>()
</script>

<template>
  <section class="geek-hero">
    <div class="geek-hero__meta">
      <span v-if="badge" class="geek-hero__badge">
        <span class="geek-hero__pulse" />
        {{ badge }}
      </span>
      <p v-if="statusLine" class="geek-hero__status">
        <span class="geek-hero__prompt">$</span> {{ statusLine }}
      </p>
    </div>

    <h1 class="geek-hero__title">
      <span class="geek-hero__title-main">{{ title }}</span>
      <span v-if="titleAccent" class="geek-hero__title-accent">{{ titleAccent }}</span>
    </h1>

    <p class="geek-hero__tagline">{{ tagline }}</p>

    <div class="geek-hero__actions">
      <a class="sm-btn sm-btn--primary" :href="primaryLink">{{ primaryText }}</a>
      <a class="sm-btn sm-btn--ghost" :href="secondaryLink">{{ secondaryText }}</a>
    </div>

    <div class="geek-hero__visual">
      <HeroStrokeHud :label="hudLabel" />
    </div>
  </section>
</template>

<style scoped>
.geek-hero {
  display: grid;
  gap: 1.25rem;
  padding: 1rem 0 2.5rem;
}

.geek-hero__meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.75rem 1.25rem;
}

.geek-hero__badge {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  font-family: var(--sm-font-mono);
  font-size: 12px;
  font-weight: 500;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--sm-accent);
  background: var(--sm-accent-glow);
  border: none;
  box-shadow: inset 0 0 0 1px var(--sm-border-strong);
  border-radius: 999px;
  padding: 0.35rem 0.85rem;
}

.geek-hero__pulse {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--sm-accent);
  box-shadow: 0 0 0 0 var(--sm-accent-glow);
  animation: pulse 1.8s ease-out infinite;
}

@keyframes pulse {
  0% {
    box-shadow: 0 0 0 0 color-mix(in srgb, var(--sm-accent) 55%, transparent);
  }
  70% {
    box-shadow: 0 0 0 8px transparent;
  }
  100% {
    box-shadow: 0 0 0 0 transparent;
  }
}

.geek-hero__status {
  margin: 0;
  font-family: var(--sm-font-mono);
  font-size: 13px;
  color: var(--sm-text-muted);
}

.geek-hero__prompt {
  color: var(--sm-accent);
  margin-right: 0.25rem;
}

.geek-hero__title {
  margin: 0;
  font-family: var(--sm-font-mono);
  font-size: clamp(2.1rem, 5vw, 3.4rem);
  font-weight: 700;
  line-height: 1.15;
  letter-spacing: -0.03em;
  display: flex;
  flex-wrap: wrap;
  gap: 0.35em;
}

.geek-hero__title-main {
  color: var(--sm-text);
}

.geek-hero__title-accent {
  background: linear-gradient(120deg, var(--sm-accent), var(--sm-cyan));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.geek-hero__tagline {
  margin: 0;
  max-width: 36rem;
  font-size: 1.1rem;
  line-height: 1.65;
  color: var(--sm-text-muted);
}

.geek-hero__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-top: 0.35rem;
}

.geek-hero__visual {
  margin-top: 1.5rem;
  min-width: 0;
}

@media (min-width: 960px) {
  .geek-hero {
    grid-template-columns: 1fr 1fr;
    grid-template-rows: auto auto auto auto;
    column-gap: 2.5rem;
    align-items: start;
  }

  .geek-hero__meta,
  .geek-hero__title,
  .geek-hero__tagline,
  .geek-hero__actions {
    grid-column: 1;
  }

  .geek-hero__visual {
    grid-column: 2;
    grid-row: 1 / span 4;
    margin-top: 0;
    align-self: center;
  }
}
</style>
