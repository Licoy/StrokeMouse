<script setup lang="ts">
import { computed, ref } from 'vue'
import { useData } from 'vitepress'
import GestureStrokeCanvas from './GestureStrokeCanvas.vue'
import { GESTURE_PATHS } from '../gesturePaths'
import { DEFAULT_GESTURE_DEMOS } from '../defaultGestureDemos'
import { useReveal } from '../composables/useReveal'

defineProps<{
  heading: string
  lead?: string
}>()

const { lang } = useData()
const isZh = computed(() => !lang.value || lang.value.startsWith('zh'))

const tiles = computed(() =>
  DEFAULT_GESTURE_DEMOS.map((d) => ({
    path: d.path,
    action: isZh.value ? d.nameZh : d.nameEn,
    trigger: isZh.value ? '右键' : 'Right button',
    points: GESTURE_PATHS[d.path] ?? [],
  })),
)

const root = ref<HTMLElement | null>(null)
useReveal(root)
</script>

<template>
  <section ref="root" class="gestures sm-section">
    <header class="gestures__head sm-reveal">
      <h2 class="sm-section__title">{{ heading }}</h2>
      <p v-if="lead" class="sm-section__lead">{{ lead }}</p>
    </header>

    <!-- 2-row grid · no horizontal scroll -->
    <div class="gestures__grid sm-reveal">
      <article v-for="(tile, i) in tiles" :key="tile.path" class="gestures__tile">
        <div class="gestures__canvas-wrap">
          <GestureStrokeCanvas
            :points="tile.points"
            :width="148"
            :height="100"
            :delay-ms="i * 160"
            :line-width="2.4"
            :start-radius="3"
          />
        </div>
        <h3 class="gestures__action">{{ tile.action }}</h3>
        <p class="gestures__trigger">{{ tile.trigger }}</p>
      </article>
    </div>
  </section>
</template>

<style scoped>
.gestures__grid {
  display: grid;
  /* Mobile: 2 cols → multi-row, no x-scroll */
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.75rem;
  overflow: visible;
  width: 100%;
}

/* Tablet / desktop: 4 cols → 7 items = 2 rows (4 + 3) */
@media (min-width: 720px) {
  .gestures__grid {
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 0.85rem;
  }
}

.gestures__tile {
  min-width: 0;
  padding: 0.9rem 0.85rem 1rem;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  box-shadow: inset 0 0 0 1px var(--sm-border);
  transition:
    box-shadow 0.25s var(--sm-ease),
    transform 0.25s var(--sm-ease);
}

.gestures__tile:hover {
  box-shadow: inset 0 0 0 1px var(--sm-border-strong);
  transform: translateY(-2px);
}

.gestures__canvas-wrap {
  display: flex;
  justify-content: center;
  margin-bottom: 0.65rem;
  border-radius: 12px;
  background: color-mix(in srgb, var(--sm-bg) 70%, var(--sm-bg-soft));
  overflow: hidden;
}

.gestures__canvas-wrap :deep(canvas) {
  max-width: 100%;
  height: auto;
}

.gestures__action {
  margin: 0 0 0.2rem;
  font-family: var(--sm-font-sans);
  font-size: 0.9rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--sm-text);
  line-height: 1.3;
  overflow-wrap: anywhere;
}

.gestures__trigger {
  margin: 0;
  font-size: 0.78rem;
  color: var(--sm-text-faint);
  font-weight: 500;
}

@media (prefers-reduced-motion: reduce) {
  .gestures__tile:hover {
    transform: none;
  }
}
</style>
