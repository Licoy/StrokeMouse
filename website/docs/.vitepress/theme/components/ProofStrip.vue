<script setup lang="ts">
import { ref } from 'vue'
import { useReveal } from '../composables/useReveal'

defineProps<{
  items: string[]
}>()

const root = ref<HTMLElement | null>(null)
useReveal(root)
</script>

<template>
  <section ref="root" class="proof-strip sm-reveal" aria-label="Product facts">
    <div class="proof-strip__inner">
      <template v-for="(item, i) in items" :key="i">
        <span class="proof-strip__item">{{ item }}</span>
        <span v-if="i < items.length - 1" class="proof-strip__dot" aria-hidden="true" />
      </template>
    </div>
  </section>
</template>

<style scoped>
.proof-strip {
  margin: 0.75rem 0 0.25rem;
  border-top: 1px solid var(--sm-border);
  border-bottom: 1px solid var(--sm-border);
  /* Fixed row height + flex center = true vertical centering */
  height: 3rem;
  display: flex;
  align-items: center;
  justify-content: center;
  box-sizing: border-box;
}

.proof-strip__inner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: center;
  gap: 0;
  width: 100%;
  padding: 0 0.75rem;
  box-sizing: border-box;
  /* Match parent height so children center against full strip */
  min-height: 100%;
}

.proof-strip__item {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  height: 1.25rem;
  font-size: 0.875rem;
  font-weight: 500;
  line-height: 1.25rem;
  color: var(--sm-text-muted);
  letter-spacing: -0.01em;
  white-space: nowrap;
}

.proof-strip__dot {
  display: inline-block;
  width: 3px;
  height: 3px;
  margin: 0 0.85rem;
  border-radius: 50%;
  background: var(--sm-text-faint);
  opacity: 0.55;
  flex-shrink: 0;
  /* Optical center with text cap-height */
  align-self: center;
}

@media (max-width: 639px) {
  .proof-strip {
    height: auto;
    min-height: 3rem;
    padding: 0.65rem 0;
  }

  .proof-strip__inner {
    gap: 0.45rem 0.85rem;
  }

  .proof-strip__dot {
    display: none;
  }
}
</style>
