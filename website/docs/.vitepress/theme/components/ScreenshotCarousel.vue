<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { Swiper, SwiperSlide } from 'swiper/vue'
import { Autoplay, Navigation, Pagination } from 'swiper/modules'
import type { Swiper as SwiperType } from 'swiper'
import { PhCaretLeft, PhCaretRight } from '@phosphor-icons/vue'
import { useReveal } from '../composables/useReveal'

import 'swiper/css'
import 'swiper/css/navigation'
import 'swiper/css/pagination'

export interface Shot {
  src: string
  alt: string
}

const props = withDefaults(
  defineProps<{
    heading?: string
    description?: string
    shots?: Shot[]
  }>(),
  {
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
const root = ref<HTMLElement | null>(null)
const reducedMotion = ref(false)
useReveal(root)

onMounted(() => {
  reducedMotion.value = window.matchMedia('(prefers-reduced-motion: reduce)').matches
})

const autoplay = computed(() =>
  reducedMotion.value
    ? false
    : {
        delay: 4000,
        disableOnInteraction: false,
        pauseOnMouseEnter: true,
      },
)

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
  <section ref="root" class="sm-showcase sm-section">
    <header v-if="heading || description" class="sm-showcase__head sm-reveal">
      <h2 v-if="heading" class="sm-section__title">{{ heading }}</h2>
      <p v-if="description" class="sm-section__lead">{{ description }}</p>
    </header>

    <div class="sm-showcase__carousel sm-reveal">
      <div class="sm-bezel">
        <div class="sm-bezel__core sm-showcase__stage">
          <Swiper
            :modules="modules"
            :slides-per-view="1"
            :loop="true"
            :grab-cursor="true"
            :simulate-touch="true"
            :allow-touch-move="true"
            :speed="450"
            :autoplay="autoplay"
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
            <PhCaretLeft :size="20" weight="bold" />
          </button>
          <button type="button" class="sm-showcase__nav sm-showcase-next" aria-label="Next">
            <PhCaretRight :size="20" weight="bold" />
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
.sm-showcase__head {
  margin-bottom: 0.25rem;
}

.sm-showcase__carousel {
  position: relative;
  max-width: 960px;
  margin: 0 auto;
}

.sm-showcase__stage {
  position: relative;
  height: 400px;
  background: var(--sm-bg-soft);
}

@media (max-width: 640px) {
  .sm-showcase__stage {
    height: 250px;
  }
}

@media (min-width: 641px) and (max-width: 959px) {
  .sm-showcase__stage {
    height: 340px;
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
  background: var(--sm-bg-soft);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 14px 18px;
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
  border-radius: 8px;
}

.sm-showcase__nav {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  z-index: 5;
  width: 42px;
  height: 42px;
  border-radius: 50%;
  border: 1px solid var(--sm-border);
  background: color-mix(in srgb, var(--sm-bg-elevated) 92%, transparent);
  color: var(--sm-text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  opacity: 0;
  pointer-events: none;
  transition:
    opacity 0.25s var(--sm-ease),
    color 0.2s var(--sm-ease),
    border-color 0.2s var(--sm-ease),
    background 0.2s var(--sm-ease);
  box-shadow: var(--sm-shadow-sm);
}

.sm-showcase__stage:hover .sm-showcase__nav {
  opacity: 1;
  pointer-events: auto;
}

.sm-showcase__nav:hover {
  color: var(--sm-accent);
  border-color: var(--sm-border-strong);
}

.sm-showcase-prev {
  left: 12px;
}

.sm-showcase-next {
  right: 12px;
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
  transition: all 0.25s var(--sm-ease);
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
  border-radius: 10px;
  border: 1px solid var(--sm-border);
  overflow: hidden;
  cursor: pointer;
  background: var(--sm-bg-elevated);
  opacity: 0.55;
  transition:
    opacity 0.2s var(--sm-ease),
    border-color 0.2s var(--sm-ease),
    box-shadow 0.2s var(--sm-ease);
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
    width: 36px;
    height: 36px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .sm-showcase__swiper :deep(.swiper-wrapper) {
    transition-duration: 0ms !important;
  }
}
</style>
