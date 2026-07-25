<script setup lang="ts">
import { ref } from 'vue'
import SmButton from './SmButton.vue'
import { useReveal } from '../composables/useReveal'

defineProps<{
  heading: string
  lead?: string
  steps: string[]
  primaryText: string
  primaryLink: string
  secondaryText: string
  secondaryLink: string
}>()

const root = ref<HTMLElement | null>(null)
useReveal(root)
</script>

<template>
  <section ref="root" class="home-cta sm-section sm-reveal">
    <div class="home-cta__band">
      <h2 class="home-cta__title">{{ heading }}</h2>
      <p v-if="lead" class="home-cta__lead">{{ lead }}</p>

      <ol v-if="steps?.length" class="home-cta__steps">
        <li v-for="(step, i) in steps" :key="i">
          <span class="home-cta__num">{{ i + 1 }}</span>
          <span class="home-cta__step-text">{{ step }}</span>
        </li>
      </ol>

      <div class="home-cta__actions">
        <SmButton :href="primaryLink">{{ primaryText }}</SmButton>
        <SmButton :href="secondaryLink" variant="ghost" :arrow="false">
          {{ secondaryText }}
        </SmButton>
      </div>
    </div>
  </section>
</template>

<style scoped>
.home-cta {
  padding-bottom: 1rem !important;
}

.home-cta__band {
  text-align: center;
  padding: 2.75rem 1.5rem 2.85rem;
  border-radius: var(--sm-radius-shell);
  background:
    radial-gradient(ellipse 70% 80% at 50% 0%, var(--sm-accent-glow), transparent 65%),
    var(--sm-panel);
  box-shadow: inset 0 0 0 1px var(--sm-border);
}

.home-cta__title {
  margin: 0;
  font-family: var(--sm-font-sans);
  font-size: clamp(1.45rem, 3vw, 1.85rem);
  font-weight: 700;
  letter-spacing: -0.03em;
  color: var(--sm-text);
  text-wrap: balance;
}

.home-cta__lead {
  margin: 0.65rem auto 0;
  max-width: 28rem;
  font-size: 1rem;
  line-height: 1.55;
  color: var(--sm-text-muted);
}

.home-cta__steps {
  list-style: none;
  margin: 1.5rem auto 0;
  padding: 0;
  width: min(28rem, 100%);
  display: flex;
  flex-direction: column;
  gap: 0.55rem;
  text-align: left;
}

.home-cta__steps li {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.7rem 0.95rem;
  border-radius: 12px;
  background: var(--sm-chrome);
  box-shadow: inset 0 0 0 1px var(--sm-border);
}

.home-cta__num {
  flex-shrink: 0;
  width: 1.5rem;
  height: 1.5rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  font-size: 12px;
  font-weight: 700;
  color: #fff;
  background: var(--sm-accent);
}

.home-cta__step-text {
  font-size: 0.92rem;
  color: var(--sm-text-muted);
  font-weight: 500;
}

.home-cta__actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 0.75rem;
  margin-top: 1.65rem;
}
</style>
