<script setup lang="ts">
import SmButton from './SmButton.vue'
import HeroStrokeHud from './HeroStrokeHud.vue'

defineProps<{
  title: string
  tagline: string
  primaryText: string
  primaryLink: string
  secondaryText: string
  secondaryLink: string
  imageSrc?: string
  imageAlt?: string
  hudLabel?: string
}>()
</script>

<template>
  <section class="product-hero">
    <div class="product-hero__copy">
      <h1 class="product-hero__title">{{ title }}</h1>
      <p class="product-hero__tagline">{{ tagline }}</p>
      <div class="product-hero__actions">
        <SmButton :href="primaryLink">{{ primaryText }}</SmButton>
        <SmButton :href="secondaryLink" variant="ghost" :arrow="false">
          {{ secondaryText }}
        </SmButton>
      </div>
    </div>

    <div class="product-hero__media">
      <div class="sm-bezel product-hero__bezel">
        <div class="sm-bezel__core product-hero__core">
          <img
            v-if="imageSrc"
            class="product-hero__shot"
            :src="imageSrc"
            :alt="imageAlt || ''"
            width="2032"
            height="1342"
            fetchpriority="high"
            decoding="async"
          />
        </div>
      </div>
      <div class="product-hero__hud">
        <HeroStrokeHud :label="hudLabel" compact />
      </div>
    </div>
  </section>
</template>

<style scoped>
.product-hero {
  display: grid;
  gap: 2rem;
  padding: 0.25rem 0 0.5rem;
  align-items: center;
}

.product-hero__copy {
  min-width: 0;
}

.product-hero__title {
  margin: 0;
  font-family: var(--sm-font-sans);
  font-size: clamp(2rem, 4.2vw, 2.85rem);
  font-weight: 700;
  line-height: 1.15;
  letter-spacing: -0.035em;
  color: var(--sm-text);
  text-wrap: balance;
  max-width: 14em;
}

.product-hero__tagline {
  margin: 0.85rem 0 0;
  max-width: 32rem;
  font-size: 1.0625rem;
  line-height: 1.6;
  color: var(--sm-text-muted);
  text-wrap: pretty;
}

.product-hero__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-top: 1.35rem;
}

.product-hero__media {
  position: relative;
  min-width: 0;
  /* Keep floating HUD from painting over fixed nav menus */
  z-index: 0;
  isolation: isolate;
}

.product-hero__bezel {
  width: 100%;
}

.product-hero__core {
  /* Let the image define height; no forced crop */
  line-height: 0;
  background: var(--sm-bg-soft);
}

.product-hero__shot {
  display: block;
  width: 100%;
  height: auto;
  vertical-align: top;
}

.product-hero__hud {
  display: none;
}

@media (min-width: 960px) {
  .product-hero {
    grid-template-columns: minmax(0, 0.92fr) minmax(0, 1.08fr);
    column-gap: 2.75rem;
    padding: 0.5rem 0 1rem;
    /* Compact: no empty 720px void */
    min-height: 0;
    align-items: center;
  }

  .product-hero__copy {
    order: 0;
  }

  .product-hero__media {
    order: 1;
  }

  .product-hero__hud {
    display: block;
    position: absolute;
    right: 4%;
    bottom: -8%;
    width: min(48%, 220px);
    z-index: 1;
    filter: drop-shadow(0 14px 28px rgba(0, 0, 0, 0.32));
    pointer-events: none;
  }
}

@media (max-width: 959px) {
  .product-hero {
    gap: 1.5rem;
  }

  .product-hero__copy {
    order: 0;
  }

  .product-hero__media {
    order: 1;
  }
}
</style>
