<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useData } from 'vitepress'
import { CheckCircle2 } from 'lucide-vue-next'
import GestureStrokeCanvas from './GestureStrokeCanvas.vue'
import { GESTURE_PATHS } from '../gesturePaths'
import {
  DEFAULT_GESTURE_DEMOS,
  toastMatchedText,
  type GestureDemo,
} from '../defaultGestureDemos'

const props = defineProps<{
  label?: string
}>()

const { lang } = useData()
const isZh = computed(() => !lang.value || lang.value.startsWith('zh'))

const demos = DEFAULT_GESTURE_DEMOS
const index = ref(0)
const toastVisible = ref(false)
const toastText = ref('')
const playKey = ref(0)
const canvasW = ref(360)
const canvasH = ref(200)
const stageRef = ref<HTMLElement | null>(null)

const current = computed<GestureDemo>(() => demos[index.value % demos.length])
const points = computed(() => GESTURE_PATHS[current.value.path] ?? [])

const labelText = computed(
  () => props.label || (isZh.value ? '轨迹捕获 · 实时' : 'stroke capture · live'),
)

const footerLeft = computed(() =>
  isZh.value ? `手势：${current.value.nameZh}` : `Gesture: ${current.value.nameEn}`,
)

let toastHideTimer = 0
let nextTimer = 0
let ro: ResizeObserver | null = null

function measure() {
  const el = stageRef.value
  if (!el) return
  const w = Math.max(240, Math.floor(el.clientWidth))
  canvasW.value = w
  // Fill stage height based on aspect of window body
  canvasH.value = Math.round(Math.min(240, Math.max(168, w * 0.5)))
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
  measure()
  ro = new ResizeObserver(() => measure())
  if (stageRef.value) ro.observe(stageRef.value)
  window.addEventListener('resize', measure)
})

onUnmounted(() => {
  ro?.disconnect()
  window.removeEventListener('resize', measure)
  window.clearTimeout(toastHideTimer)
  window.clearTimeout(nextTimer)
})

watch(index, async () => {
  await nextTick()
  measure()
})
</script>

<template>
  <div class="hero-hud" aria-hidden="true">
    <div class="hero-hud__bar">
      <span class="dot red" /><span class="dot yellow" /><span class="dot green" />
      <span class="hero-hud__label">{{ labelText }}</span>
    </div>

    <!-- Full-bleed content: canvas fills window body (no nested card) -->
    <div ref="stageRef" class="hero-hud__stage">
      <GestureStrokeCanvas
        :key="playKey"
        class="hero-hud__canvas"
        :points="points"
        :width="canvasW"
        :height="canvasH"
        :loop="false"
        :line-width="3.2"
        :start-radius="4"
        @complete="onStrokeComplete"
      />

      <Transition name="hud-toast">
        <div v-if="toastVisible" class="hero-hud__toast">
          <CheckCircle2 class="hero-hud__toast-icon" :size="13" :stroke-width="2.25" />
          <span class="hero-hud__toast-text">{{ toastText }}</span>
        </div>
      </Transition>
    </div>

    <div class="hero-hud__footer">
      <span>{{ footerLeft }}</span>
      <span class="ok">{{ isZh ? '匹配成功' : 'Matched' }}</span>
    </div>
  </div>
</template>

<style scoped>
.hero-hud {
  border: none;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
  box-shadow: var(--sm-ring), var(--sm-shadow);
  overflow: hidden;
  max-width: 560px;
  width: 100%;
}

.hero-hud__bar {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0.7rem 1rem;
  border-bottom: 1px solid var(--sm-border);
  background: var(--sm-chrome);
}

.dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}
.dot.red {
  background: #ff5f57;
}
.dot.yellow {
  background: #febc2e;
}
.dot.green {
  background: #28c840;
}

.hero-hud__label {
  margin-left: 0.5rem;
  font-family: var(--sm-font-mono);
  font-size: 11px;
  color: var(--sm-text-faint);
  letter-spacing: 0.04em;
}

.hero-hud__stage {
  position: relative;
  width: 100%;
  margin: 0;
  padding: 0;
  box-sizing: border-box;
  line-height: 0;
  background: color-mix(in srgb, var(--sm-bg) 70%, var(--sm-bg-soft));
}

/* Canvas fills the window body edge-to-edge — no inner card chrome */
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

/* Smaller toast, raised slightly above bottom */
.hero-hud__toast {
  position: absolute;
  left: 50%;
  bottom: 2.15rem;
  transform: translateX(-50%);
  display: inline-flex;
  align-items: center;
  gap: 5px;
  max-width: calc(100% - 2.5rem);
  padding: 5px 10px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--sm-bg-elevated) 82%, transparent);
  backdrop-filter: blur(14px) saturate(1.15);
  -webkit-backdrop-filter: blur(14px) saturate(1.15);
  box-shadow:
    0 2px 8px rgba(0, 0, 0, 0.16),
    inset 0 0 0 1px color-mix(in srgb, var(--sm-border) 70%, transparent);
  font-family: system-ui, -apple-system, 'SF Pro Text', 'Segoe UI', sans-serif;
  font-size: 11px;
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
  width: 13px;
  height: 13px;
  color: #34c759;
}

.hero-hud__toast-text {
  overflow: hidden;
  text-overflow: ellipsis;
}

.hud-toast-enter-active,
.hud-toast-leave-active {
  transition:
    opacity 0.16s ease,
    transform 0.16s ease;
}

.hud-toast-enter-from,
.hud-toast-leave-to {
  opacity: 0;
  transform: translateX(-50%) translateY(5px);
}

.hero-hud__footer {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.6rem 1rem 0.75rem;
  border-top: 1px solid var(--sm-border);
  background: var(--sm-chrome);
  font-family: var(--sm-font-mono);
  font-size: 11px;
  color: var(--sm-text-faint);
  letter-spacing: 0.03em;
  line-height: normal;
}

.hero-hud__footer .ok {
  color: var(--sm-accent);
}

@media (min-width: 960px) {
  .hero-hud {
    max-width: none;
  }
}
</style>
