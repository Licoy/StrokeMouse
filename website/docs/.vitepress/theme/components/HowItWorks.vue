<script setup lang="ts">
import { ref } from 'vue'
import { useReveal } from '../composables/useReveal'

export interface HowStep {
  title: string
  desc: string
}

defineProps<{
  heading: string
  steps: HowStep[]
}>()

const root = ref<HTMLElement | null>(null)
useReveal(root)
</script>

<template>
  <section ref="root" class="how sm-section">
    <h2 class="sm-section__title sm-reveal">{{ heading }}</h2>
    <ol class="how__grid">
      <li
        v-for="(step, i) in steps"
        :key="i"
        class="how__card sm-reveal"
        :style="{ transitionDelay: `${i * 70}ms` }"
      >
        <span class="how__title">{{ step.title }}</span>
        <p class="how__desc">{{ step.desc }}</p>
      </li>
    </ol>
  </section>
</template>

<style scoped>
.how__grid {
  list-style: none;
  margin: 1.75rem 0 0;
  padding: 0;
  display: grid;
  grid-template-columns: 1fr;
  gap: 0.85rem;
}

@media (min-width: 768px) {
  .how__grid {
    grid-template-columns: repeat(3, 1fr);
    gap: 1rem;
  }
}

.how__card {
  margin: 0;
  padding: 1.35rem 1.25rem 1.4rem;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  box-shadow: inset 0 0 0 1px var(--sm-border);
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
  transition:
    box-shadow 0.25s var(--sm-ease),
    transform 0.25s var(--sm-ease);
}

.how__card:hover {
  box-shadow: inset 0 0 0 1px var(--sm-border-strong);
  transform: translateY(-2px);
}

.how__title {
  font-family: var(--sm-font-sans);
  font-size: 1.05rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--sm-text);
}

.how__desc {
  margin: 0;
  font-size: 0.92rem;
  line-height: 1.55;
  color: var(--sm-text-muted);
}
</style>
