<script setup lang="ts">
import { ref } from 'vue'

const props = withDefaults(
  defineProps<{
    heading?: string
    description?: string
    playLabel?: string
    src?: string
    poster?: string
    duration?: string
  }>(),
  {
    playLabel: 'Play video',
    src: '/video/strokemouse-promo.mp4',
    poster: '/video/strokemouse-promo-poster.jpg',
    duration: '1:42',
  },
)

const video = ref<HTMLVideoElement | null>(null)
const started = ref(false)

// preload="none"：首页不预先下载视频，点击播放才开始加载
function play() {
  started.value = true
  void video.value?.play()
}
</script>

<template>
  <section id="video" class="hd-video">
    <div v-if="heading || description" class="hd-video-header">
      <h2 v-if="heading" class="hd-video-title">{{ heading }}</h2>
      <p v-if="description" class="hd-video-lead">{{ description }}</p>
    </div>

    <div class="hd-video-frame">
      <div class="hd-video-bar">
        <div class="hd-video-bar-left">
          <span class="hd-video-dot" />
          <span class="hd-video-dot" />
          <span class="hd-video-dot" />
          <span class="hd-video-name">StrokeMouse</span>
        </div>
        <span class="hd-video-meta">{{ props.duration }} · 1080p60</span>
      </div>

      <div class="hd-video-stage">
        <video
          ref="video"
          :src="props.src"
          :poster="props.poster"
          :controls="started"
          preload="none"
          playsinline
          @play="started = true"
        />
        <button
          v-if="!started"
          type="button"
          class="hd-video-play"
          :aria-label="`${playLabel} (${props.duration})`"
          @click="play"
        >
          <span class="hd-video-play-btn">
            <span class="hd-video-play-icon" aria-hidden="true">
              <svg viewBox="0 0 10 12"><path d="M0 0 L10 6 L0 12 Z" /></svg>
            </span>
            <span class="hd-video-play-text">{{ playLabel }}</span>
            <span class="hd-video-play-time">{{ props.duration }}</span>
          </span>
        </button>
      </div>
    </div>
  </section>
</template>

<style scoped>
.hd-video {
  padding: 48px var(--gut);
  border-bottom: 1px solid var(--line2);
  background: var(--bg);
  scroll-margin-top: var(--vp-nav-height, 64px);
}

.hd-video-header {
  margin-bottom: 28px;
}

.hd-video-title {
  font-family: var(--disp);
  font-weight: 900;
  font-size: clamp(26px, 3.5vw, 44px);
  letter-spacing: -0.04em;
  color: var(--ink);
  line-height: 1.05;
  margin: 0;
}

.hd-video-lead {
  color: var(--dim);
  font-size: 15px;
  line-height: 1.7;
  max-width: 60ch;
  margin: 12px 0 0;
}

.hd-video-frame {
  border: 1px solid var(--line2);
  background: var(--panel);
}

.hd-video-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 16px;
  border-bottom: 1px solid var(--line2);
  background: color-mix(in srgb, var(--panel) 94%, black);
  font-size: 11.5px;
}

.hd-video-bar-left {
  display: flex;
  align-items: center;
  gap: 8px;
}

.hd-video-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--line2);
}

.hd-video-name {
  margin-left: 8px;
  color: var(--ink);
  font-weight: 500;
}

.hd-video-meta {
  font-family: var(--mono);
  font-size: 10.5px;
  color: var(--faint);
  font-variant-numeric: tabular-nums;
  letter-spacing: 0.08em;
}

.hd-video-stage {
  position: relative;
  aspect-ratio: 16 / 9;
  background: #050b18;
  line-height: 0;
}

.hd-video-stage video {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: #050b18;
}

/* 整个画面都可点击；按钮放在右下角，避开海报中央的 Logo 与标语 */
.hd-video-play {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: flex-end;
  justify-content: flex-end;
  padding: clamp(12px, 3%, 32px);
  border: 0;
  background: transparent;
  cursor: pointer;
}

.hd-video-play-btn {
  display: inline-flex;
  align-items: center;
  gap: 12px;
  padding: 8px 16px 8px 8px;
  border: 1px solid color-mix(in srgb, #38bdf8 55%, transparent);
  background: rgba(8, 16, 34, 0.78);
  color: #eae8ee;
  font-family: var(--body);
  font-size: 14px;
  font-weight: 600;
  line-height: 1;
  transition: border-color 0.12s ease, background-color 0.12s ease;
}

.hd-video-play:hover .hd-video-play-btn,
.hd-video-play:focus-visible .hd-video-play-btn {
  border-color: #38bdf8;
  background: rgba(8, 16, 34, 0.92);
}

.hd-video-play:focus-visible {
  outline: 2px solid #38bdf8;
  outline-offset: -2px;
}

.hd-video-play-icon {
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  background: #38bdf8;
}

.hd-video-play-icon svg {
  width: 12px;
  height: 12px;
  margin-left: 2px;
  fill: #0b1120;
}

.hd-video-play-time {
  font-family: var(--mono);
  font-size: 12px;
  font-weight: 500;
  color: #b0afb6;
  font-variant-numeric: tabular-nums;
}

@media (max-width: 500px) {
  .hd-video-play {
    padding: 8px;
  }
  .hd-video-play-text {
    display: none;
  }
  .hd-video-play-btn {
    gap: 6px;
    padding: 4px 8px 4px 4px;
  }
  .hd-video-play-icon {
    width: 22px;
    height: 22px;
  }
  .hd-video-play-icon svg {
    width: 8px;
    height: 8px;
    margin-left: 1px;
  }
  .hd-video-play-time {
    font-size: 10.5px;
  }
}
</style>
