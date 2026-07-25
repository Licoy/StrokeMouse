<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useData } from 'vitepress'
import { PhCheckCircle } from '@phosphor-icons/vue'
import GestureStrokeCanvas from './GestureStrokeCanvas.vue'
import { GESTURE_PATHS } from '../gesturePaths'
import {
  DEFAULT_GESTURE_DEMOS,
  toastMatchedText,
  type GestureDemo,
} from '../defaultGestureDemos'

const props = withDefaults(
  defineProps<{
    label?: string
    compact?: boolean
  }>(),
  { compact: false },
)

const { lang } = useData()
const isZh = computed(() => !lang.value || lang.value.startsWith('zh'))

const demos = DEFAULT_GESTURE_DEMOS
const index = ref(0)
const toastVisible = ref(false)
const toastText = ref('')
const playKey = ref(0)
const canvasW = ref(props.compact ? 200 : 360)
const canvasH = ref(props.compact ? 120 : 200)
const stageRef = ref<HTMLElement | null>(null)
const reduced = ref(false)

const current = computed<GestureDemo>(() => demos[index.value % demos.length])
const points = computed(() => GESTURE_PATHS[current.value.path] ?? [])

const labelText = computed(
  () => props.label || (isZh.value ? '轨迹捕获' : 'Stroke capture'),
)

const footerLeft = computed(() =>
  isZh.value ? current.value.nameZh : current.value.nameEn,
)

let toastHideTimer = 0
let nextTimer = 0
let ro: ResizeObserver | null = null

function measure() {
  const el = stageRef.value
  if (!el) return
  const w = Math.max(160, Math.floor(el.clientWidth))
  canvasW.value = w
  canvasH.value = Math.round(
    Math.min(props.compact ? 140 : 240, Math.max(props.compact ? 100 : 168, w * 0.52)),
  )
}

function showToast(demo: GestureDemo) {
  const name = isZh.value ? demo.nameZh : demo.nameEn
  toastText.value = toastMatchedText(name, demo.score, isZh.value)
  toastVisible.value = true
  window.clearTimeout(toastHideTimer)
  toastHideTimer = window.setTimeout(() => {
    toastVisible.value = false
  }, 1600)
}

function onStrokeComplete() {
  if (reduced.value) return
  const demo = current.value
  showToast(demo)
  window.clearTimeout(nextTimer)
  nextTimer = window.setTimeout(() => {
    toastVisible.value = false
    index.value = (index.value + 1) % demos.length
    playKey.value += 1
  }, 1900)
}

onMounted(() => {
  reduced.value = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  measure()
  ro = new ResizeObserver(() => measure())
  if (stageRef.value) ro.observe(stageRef.value)
})

onUnmounted(() => {
  ro?.disconnect()
  window.clearTimeout(toastHideTimer)
  window.clearTimeout(nextTimer)
})

watch(index, async () => {
  await nextTick()
  measure()
})
</script>

<template>
  <div class="hero-hud" :class="{ 'hero-hud--compact': compact }" aria-hidden="true">
    <div class="hero-hud__bar">
      <span class="hero-hud__label">{{ labelText }}</span>
    </div>

    <div ref="stageRef" class="hero-hud__stage">
      <GestureStrokeCanvas
        :key="playKey"
        class="hero-hud__canvas"
        :points="points"
        :width="canvasW"
        :height="canvasH"
        :loop="false"
        :line-width="compact ? 2.6 : 3.2"
        :start-radius="compact ? 3 : 4"
        @complete="onStrokeComplete"
      />

      <Transition name="hud-toast">
        <div v-if="toastVisible" class="hero-hud__toast">
          <PhCheckCircle class="hero-hud__toast-icon" :size="13" weight="fill" />
          <span class="hero-hud__toast-text">{{ toastText }}</span>
        </div>
      </Transition>
    </div>

    <div class="hero-hud__footer">
      <span class="hero-hud__name">{{ footerLeft }}</span>
      <span class="ok">{{ isZh ? '已匹配' : 'Matched' }}</span>
    </div>
  </div>
</template>

<style scoped>
.hero-hud {
  border-radius: 14px;
  background: color-mix(in srgb, var(--sm-bg-elevated) 92%, transparent);
  backdrop-filter: blur(12px) saturate(1.15);
  -webkit-backdrop-filter: blur(12px) saturate(1.15);
  box-shadow:
    inset 0 0 0 1px var(--sm-border),
    0 12px 32px rgba(0, 0, 0, 0.28);
  overflow: hidden;
  width: 100%;
}

.hero-hud__bar {
  display: flex;
  align-items: center;
  padding: 0.45rem 0.7rem;
  border-bottom: 1px solid var(--sm-border);
  background: var(--sm-chrome);
}

.hero-hud__label {
  font-family: var(--sm-font-sans);
  font-size: 10px;
  font-weight: 600;
  color: var(--sm-text-faint);
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.hero-hud__stage {
  position: relative;
  width: 100%;
  margin: 0;
  padding: 0;
  box-sizing: border-box;
  line-height: 0;
  background: color-mix(in srgb, var(--sm-bg) 75%, var(--sm-bg-soft));
}

.hero-hud__canvas {
  display: block !important;
  width: 100% !important;
  max-width: none !important;
  height: auto !important;
  margin: 0 !important;
  border-radius: 0 !important;
  background: transparent !important;
  box-shadow: none !important;
}

.hero-hud__toast {
  position: absolute;
  left: 50%;
  bottom: 0.65rem;
  transform: translateX(-50%);
  display: inline-flex;
  align-items: center;
  gap: 5px;
  max-width: calc(100% - 1.25rem);
  padding: 4px 8px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--sm-bg-elevated) 88%, transparent);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  box-shadow: inset 0 0 0 1px var(--sm-border);
  font-family: var(--sm-font-sans);
  font-size: 10px;
  font-weight: 500;
  line-height: 1.2;
  color: var(--sm-text);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  pointer-events: none;
  z-index: 2;
}

.hero-hud__toast-icon {
  flex-shrink: 0;
  color: var(--sm-accent);
}

.hero-hud__toast-text {
  overflow: hidden;
  text-overflow: ellipsis;
}

.hud-toast-enter-active,
.hud-toast-leave-active {
  transition:
    opacity 0.2s var(--sm-ease),
    transform 0.2s var(--sm-ease);
}

.hud-toast-enter-from,
.hud-toast-leave-to {
  opacity: 0;
  transform: translateX(-50%) translateY(4px);
}

.hero-hud__footer {
  display: flex;
  justify-content: space-between;
  gap: 0.5rem;
  padding: 0.4rem 0.7rem 0.5rem;
  border-top: 1px solid var(--sm-border);
  background: var(--sm-chrome);
  font-family: var(--sm-font-sans);
  font-size: 10px;
  font-weight: 500;
  color: var(--sm-text-faint);
  line-height: normal;
}

.hero-hud__name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.hero-hud__footer .ok {
  color: var(--sm-accent);
  flex-shrink: 0;
}

.hero-hud--compact .hero-hud__bar {
  padding: 0.35rem 0.55rem;
}

.hero-hud--compact .hero-hud__footer {
  padding: 0.3rem 0.55rem 0.4rem;
}

@media (prefers-reduced-motion: reduce) {
  .hud-toast-enter-active,
  .hud-toast-leave-active {
    transition: none;
  }
}

@media (prefers-reduced-transparency: reduce) {
  .hero-hud {
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
    background: var(--sm-bg-elevated);
  }
}
</style>
