<script setup lang="ts">
import { onMounted, onUnmounted, ref, watch } from 'vue'

export type Point = { x: number; y: number }

const props = withDefaults(
  defineProps<{
    /** Template points in unit space (y-up, 0–1) */
    points: Point[]
    width?: number
    height?: number
    /** Stagger delay so rows don't all animate in sync */
    delayMs?: number
    /** When false, play once and emit `complete` after hold */
    loop?: boolean
    lineWidth?: number
    startRadius?: number
  }>(),
  {
    width: 52,
    height: 52,
    delayMs: 0,
    loop: true,
    lineWidth: 2.4,
    startRadius: 3,
  },
)

const emit = defineEmits<{
  complete: []
  progress: [value: number]
}>()

const canvasRef = ref<HTMLCanvasElement | null>(null)
let raf = 0
let start = 0
let delayTimer = 0
let completed = false

function toCanvasPoints(w: number, h: number, pad: number): Point[] {
  const pts = props.points
  if (!pts.length) return []
  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  for (const p of pts) {
    minX = Math.min(minX, p.x)
    minY = Math.min(minY, p.y)
    maxX = Math.max(maxX, p.x)
    maxY = Math.max(maxY, p.y)
  }
  const spanX = Math.max(maxX - minX, 0.01)
  const spanY = Math.max(maxY - minY, 0.01)
  const box = Math.min(w, h) - pad * 2
  const scale = box / Math.max(spanX, spanY)
  const ox = (w - spanX * scale) / 2
  const oy = (h - spanY * scale) / 2
  return pts.map((p) => ({
    x: ox + (p.x - minX) * scale,
    y: oy + (maxY - p.y) * scale,
  }))
}

function getAccent(): string {
  if (typeof window === 'undefined') return '#3898f8'
  return (
    getComputedStyle(document.documentElement).getPropertyValue('--sm-accent').trim() ||
    '#3898f8'
  )
}

function drawFrame(progress: number) {
  const canvas = canvasRef.value
  if (!canvas) return
  const dpr = window.devicePixelRatio || 1
  const w = props.width
  const h = props.height
  if (canvas.width !== w * dpr || canvas.height !== h * dpr) {
    canvas.width = w * dpr
    canvas.height = h * dpr
    canvas.style.width = `${w}px`
    canvas.style.height = `${h}px`
  }
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.clearRect(0, 0, w, h)

  const pad = Math.max(8, Math.min(w, h) * 0.1)
  const pts = toCanvasPoints(w, h, pad)
  if (pts.length < 2) return

  // Soft grid (same style as default-gesture cells)
  ctx.strokeStyle = 'rgba(128,140,160,0.12)'
  ctx.lineWidth = 1
  const gridN = w > 120 ? 6 : 4
  for (let i = 1; i < gridN; i++) {
    const x = (w * i) / gridN
    const y = (h * i) / gridN
    ctx.beginPath()
    ctx.moveTo(x, pad * 0.4)
    ctx.lineTo(x, h - pad * 0.4)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(pad * 0.4, y)
    ctx.lineTo(w - pad * 0.4, y)
    ctx.stroke()
  }

  let total = 0
  for (let i = 1; i < pts.length; i++) {
    total += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
  }

  const accent = getAccent()
  const drawLen = total * Math.min(Math.max(progress, 0), 1)
  const lw = props.lineWidth

  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  ctx.strokeStyle = accent
  ctx.lineWidth = lw
  ctx.shadowColor = accent
  ctx.shadowBlur = Math.max(4, lw * 2)

  ctx.beginPath()
  ctx.moveTo(pts[0].x, pts[0].y)
  let walked = 0
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1]
    const b = pts[i]
    const seg = Math.hypot(b.x - a.x, b.y - a.y)
    if (walked + seg <= drawLen) {
      ctx.lineTo(b.x, b.y)
      walked += seg
    } else {
      const t = (drawLen - walked) / seg
      ctx.lineTo(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
      break
    }
  }
  ctx.stroke()
  ctx.shadowBlur = 0

  // Start only — red
  const r = props.startRadius
  ctx.fillStyle = '#ff4d4f'
  ctx.beginPath()
  ctx.arc(pts[0].x, pts[0].y, r, 0, Math.PI * 2)
  ctx.fill()
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)'
  ctx.lineWidth = 1
  ctx.stroke()
}

function loop(ts: number) {
  if (!start) start = ts
  const elapsed = ts - start

  if (props.loop) {
    const cycle = 2000
    const t = (elapsed % cycle) / cycle
    let progress: number
    if (t < 0.55) progress = t / 0.55
    else if (t < 0.85) progress = 1
    else progress = 0
    drawFrame(progress)
    emit('progress', progress)
    raf = requestAnimationFrame(loop)
    return
  }

  // once: draw 1.15s, hold 0.55s, then complete
  const drawMs = 1150
  const holdMs = 550
  if (elapsed < drawMs) {
    const progress = elapsed / drawMs
    drawFrame(progress)
    emit('progress', progress)
    raf = requestAnimationFrame(loop)
  } else if (elapsed < drawMs + holdMs) {
    drawFrame(1)
    emit('progress', 1)
    raf = requestAnimationFrame(loop)
  } else {
    drawFrame(1)
    if (!completed) {
      completed = true
      emit('complete')
    }
  }
}

function startAnim() {
  cancelAnimationFrame(raf)
  window.clearTimeout(delayTimer)
  start = 0
  completed = false
  delayTimer = window.setTimeout(() => {
    raf = requestAnimationFrame(loop)
  }, props.delayMs)
}

onMounted(() => {
  startAnim()
})

onUnmounted(() => {
  cancelAnimationFrame(raf)
  window.clearTimeout(delayTimer)
})

watch(
  () => [props.points, props.loop, props.width, props.height] as const,
  () => startAnim(),
  { deep: true },
)

defineExpose({ restart: startAnim })
</script>

<template>
  <canvas
    ref="canvasRef"
    class="stroke-canvas"
    :width="width"
    :height="height"
    role="img"
    aria-hidden="true"
  />
</template>

<style scoped>
.stroke-canvas {
  display: block;
  width: v-bind(width + 'px');
  height: v-bind(height + 'px');
  border-radius: 8px;
  background: color-mix(in srgb, var(--sm-bg) 55%, var(--sm-bg-soft));
  box-shadow: inset 0 0 0 1px var(--sm-border);
  flex-shrink: 0;
}
</style>
