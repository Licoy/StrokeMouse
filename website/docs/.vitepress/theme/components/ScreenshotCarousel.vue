<script setup lang="ts">
import { ref } from 'vue'
import { Swiper, SwiperSlide } from 'swiper/vue'
import { Autoplay, Navigation, Pagination } from 'swiper/modules'
import type { Swiper as SwiperType } from 'swiper'
import { ChevronLeft, ChevronRight } from 'lucide-vue-next'

import 'swiper/css'
import 'swiper/css/navigation'
import 'swiper/css/pagination'

export interface Shot {
  src: string
  alt: string
}

const props = withDefaults(
  defineProps<{
    subheading?: string
    heading?: string
    description?: string
    frameTag?: string
    framePath?: string
    shots?: Shot[]
  }>(),
  {
    frameTag: 'Preview',
    framePath: '~/StrokeMouse/screenshots',
    shots: () => [
      { src: '/screenshots/1.png', alt: 'Gesture list' },
      { src: '/screenshots/2.png', alt: 'Gesture test' },
      { src: '/screenshots/3.png', alt: 'General settings' },
      { src: '/screenshots/4.png', alt: 'Permissions' },
      { src: '/screenshots/5.png', alt: 'Record stroke' },
      { src: '/screenshots/6.png', alt: 'App scope' },
    ],
  },
)

const modules = [Autoplay, Navigation, Pagination]
const active = ref(0)
const swiperRef = ref<SwiperType | null>(null)

function onSwiper(swiper: SwiperType) {
  swiperRef.value = swiper
}

function goTo(i: number) {
  swiperRef.value?.slideToLoop(i)
}

function onSlideChange(swiper: SwiperType) {
  active.value = swiper.realIndex
}
</script>

<template>
  <section class="sm-showcase">
    <header v-if="heading || subheading || description" class="sm-showcase__head">
      <p v-if="subheading" class="sm-showcase__kicker">{{ subheading }}</p>
      <h2 v-if="heading" class="sm-showcase__heading">{{ heading }}</h2>
      <p v-if="description" class="sm-showcase__desc">{{ description }}</p>
    </header>

    <div class="sm-showcase__carousel">
      <div class="sm-showcase__frame">
        <div class="sm-showcase__frame-bar">
          <span class="sm-showcase__frame-tag">{{ frameTag }}</span>
          <span class="sm-showcase__frame-path">{{ framePath }}</span>
        </div>
        <div class="sm-showcase__stage">
          <Swiper
            :modules="modules"
            :slides-per-view="1"
            :loop="true"
            :grab-cursor="true"
            :simulate-touch="true"
            :allow-touch-move="true"
            :speed="450"
            :autoplay="{
              delay: 3500,
              disableOnInteraction: false,
              pauseOnMouseEnter: true,
            }"
            :navigation="{
              nextEl: '.sm-showcase-next',
              prevEl: '.sm-showcase-prev',
            }"
            :pagination="{ clickable: true, el: '.sm-showcase__pagination' }"
            class="sm-showcase__swiper"
            @swiper="onSwiper"
            @slide-change="onSlideChange"
          >
            <SwiperSlide v-for="(shot, i) in props.shots" :key="shot.src">
              <img
                :src="shot.src"
                :alt="shot.alt"
                :loading="i === 0 ? 'eager' : 'lazy'"
                draggable="false"
              />
            </SwiperSlide>
          </Swiper>

          <button type="button" class="sm-showcase__nav sm-showcase-prev" aria-label="Previous">
            <ChevronLeft :size="22" />
          </button>
          <button type="button" class="sm-showcase__nav sm-showcase-next" aria-label="Next">
            <ChevronRight :size="22" />
          </button>
        </div>
      </div>
    </div>

    <div class="sm-showcase__pagination" />

    <div class="sm-showcase__thumbs" role="tablist">
      <button
        v-for="(shot, i) in props.shots"
        :key="shot.src"
        type="button"
        class="sm-showcase__thumb"
        :class="{ active: active === i }"
        :aria-selected="active === i"
        :aria-label="shot.alt"
        @click="goTo(i)"
      >
        <img :src="shot.src" :alt="shot.alt" loading="lazy" draggable="false" />
      </button>
    </div>
  </section>
</template>

<style scoped>
.sm-showcase {
  margin: 2.5rem 0 2rem;
}

.sm-showcase__head {
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-bottom: 1.75rem;
}

.sm-showcase__kicker {
  margin: 0 0 0.4rem;
  font-family: var(--sm-font-mono);
  font-size: 12px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--sm-accent);
}

/* Override .vp-doc h2 border-top / padding (doc section divider) */
h2.sm-showcase__heading {
  margin: 0;
  margin-top: 0 !important;
  padding-top: 0 !important;
  border-top: none !important;
  font-family: var(--sm-font-mono);
  font-size: 1.45rem;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--sm-text);
}

.sm-showcase__desc {
  margin: 0.65rem 0 0;
  max-width: 36rem;
  font-size: 0.95rem;
  line-height: 1.55;
  color: var(--sm-text-muted);
}

.sm-showcase__carousel {
  position: relative;
  max-width: 960px;
  margin: 0 auto;
}

.sm-showcase__frame {
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  box-shadow:
    inset 0 0 0 1px var(--sm-border),
    var(--sm-shadow);
  overflow: hidden;
}

.sm-showcase__frame-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  background: var(--sm-bg-elevated);
  border-bottom: 1px solid var(--sm-border);
  font-family: var(--sm-font-mono);
  font-size: 11px;
}

.sm-showcase__frame-tag {
  color: var(--sm-accent);
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

.sm-showcase__frame-path {
  color: var(--sm-text-faint);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sm-showcase__stage {
  position: relative;
  height: 380px;
  background: var(--sm-bg-elevated);
}

@media (max-width: 640px) {
  .sm-showcase__stage {
    height: 240px;
  }
}

@media (min-width: 641px) and (max-width: 959px) {
  .sm-showcase__stage {
    height: 320px;
  }
}

.sm-showcase__swiper {
  width: 100%;
  height: 100%;
  cursor: grab;
  user-select: none;
  touch-action: pan-y;
}

.sm-showcase__swiper:active {
  cursor: grabbing;
}

.sm-showcase__swiper :deep(.swiper-wrapper),
.sm-showcase__swiper :deep(.swiper-slide) {
  height: 100%;
}

.sm-showcase__swiper :deep(.swiper-slide) {
  background: var(--sm-bg-elevated);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 12px 16px;
  box-sizing: border-box;
}

.sm-showcase__swiper :deep(img) {
  display: block;
  max-width: 100%;
  max-height: 100%;
  width: auto;
  height: auto;
  object-fit: contain;
  pointer-events: none;
}

.sm-showcase__nav {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  z-index: 5;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  border: 1px solid var(--sm-border);
  background: var(--sm-bg-elevated);
  color: var(--sm-text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  opacity: 0;
  pointer-events: none;
  transition:
    opacity 0.2s ease,
    color 0.2s ease,
    border-color 0.2s ease,
    box-shadow 0.2s ease,
    background 0.2s ease;
  box-shadow: var(--sm-shadow-sm);
}

.sm-showcase__stage:hover .sm-showcase__nav {
  opacity: 1;
  pointer-events: auto;
}

.sm-showcase__nav:hover {
  color: var(--sm-accent);
  border-color: var(--sm-border-strong);
  background: var(--sm-bg-soft);
  box-shadow: 0 0 0 1px var(--sm-accent-glow), var(--sm-shadow-sm);
}

.sm-showcase-prev {
  left: 10px;
}

.sm-showcase-next {
  right: 10px;
}

@media (hover: none), (pointer: coarse) {
  .sm-showcase__nav {
    opacity: 0.92;
    pointer-events: auto;
  }
}

.sm-showcase__pagination {
  display: flex;
  justify-content: center;
  gap: 6px;
  margin-top: 16px;
  min-height: 10px;
}

.sm-showcase__pagination :deep(.swiper-pagination-bullet) {
  width: 8px;
  height: 8px;
  border-radius: 4px;
  background: var(--sm-text-faint);
  opacity: 0.4;
  margin: 0 !important;
  transition: all 0.25s ease;
}

.sm-showcase__pagination :deep(.swiper-pagination-bullet-active) {
  width: 22px;
  background: var(--sm-accent);
  opacity: 1;
}

.sm-showcase__thumbs {
  display: flex;
  justify-content: center;
  gap: 8px;
  margin-top: 16px;
  flex-wrap: wrap;
  max-width: 960px;
  margin-left: auto;
  margin-right: auto;
}

.sm-showcase__thumb {
  width: 72px;
  height: 48px;
  padding: 0;
  border-radius: 8px;
  border: 1px solid var(--sm-border);
  overflow: hidden;
  cursor: pointer;
  background: var(--sm-bg-elevated);
  opacity: 0.55;
  transition:
    opacity 0.2s ease,
    border-color 0.2s ease,
    box-shadow 0.2s ease;
}

.sm-showcase__thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.sm-showcase__thumb:hover {
  opacity: 0.85;
}

.sm-showcase__thumb.active {
  opacity: 1;
  border-color: var(--sm-border-strong);
  box-shadow: 0 0 0 1px var(--sm-accent-glow);
}

@media (max-width: 640px) {
  .sm-showcase__thumb {
    width: 56px;
    height: 38px;
  }

  .sm-showcase__nav {
    width: 38px;
    height: 38px;
  }

  .sm-showcase-prev {
    left: 8px;
  }
  .sm-showcase-next {
    right: 8px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .sm-showcase__swiper :deep(.swiper-wrapper) {
    transition-duration: 0ms !important;
  }
}
</style>
