<script setup lang="ts">
import { computed } from 'vue'
import { localeHref, useSiteLocale } from '../i18n'

export interface BentoItem {
  icon?: string
  title: string
  desc: string
  /** Locale-relative docs path. Defaults to the gestures guide. */
  href?: string
  size?: 'large' | 'media' | 'default'
  image?: string
  imageAlt?: string
}

defineProps<{
  heading: string
  lead?: string
  items: BentoItem[]
}>()

const locale = useSiteLocale()
const docsLink = computed(() => localeHref(locale.value, '/guide/gestures'))
</script>

<template>
  <section class="hd-capabilities">
    <div class="hd-caps-header">
      <h2 class="hd-caps-title">{{ heading }}</h2>
      <p v-if="lead" class="hd-caps-lead">{{ lead }}</p>
    </div>

    <!-- ── 1-8 Full-Width Horizontal Rows ── -->
    <div class="caps">
      <a
        v-for="(item, i) in items"
        :key="i"
        class="cap"
        :href="item.href ? localeHref(locale, item.href) : docsLink"
      >
        <div class="n">
          <span>0{{ i + 1 }}</span>
        </div>

        <div class="cap-title-col">
          <h3 class="cap-title">
            <span>{{ item.title }}</span>
            <span class="arw" aria-hidden="true">→</span>
          </h3>
        </div>

        <div class="cap-desc-col">
          <p class="cap-desc">{{ item.desc }}</p>
        </div>
      </a>
    </div>
  </section>
</template>

<style scoped>
.hd-capabilities {
  background: var(--bg);
  border-bottom: 1px solid var(--line2);
}

.hd-caps-header {
  padding: 48px var(--gut) 28px;
}

.hd-caps-title {
  font-family: var(--disp);
  font-weight: 900;
  font-size: clamp(26px, 3.6vw, 48px);
  letter-spacing: -0.04em;
  color: var(--ink);
  line-height: 1.05;
  margin: 0;
}

.hd-caps-lead {
  color: var(--dim);
  font-size: 15px;
  line-height: 1.7;
  max-width: 64ch;
  margin: 12px 0 0;
}

/* ── Full-Width Horizontal Rows ── */
.caps {
  border-top: 1px solid var(--line2);
  border-bottom: 1px solid var(--line2);
}

.cap {
  display: grid;
  grid-template-columns: 72px 280px 1fr;
  gap: 0 28px;
  align-items: center;
  padding: 20px var(--gut);
  border-bottom: 1px solid var(--line);
  text-decoration: none !important;
  cursor: pointer;
  background: var(--bg);
  transition: background-color 0.12s ease;
  box-sizing: border-box;
}

.cap:last-child {
  border-bottom: 0;
}

.cap:hover {
  background: color-mix(in srgb, var(--spot) 5%, var(--bg));
}

.cap:hover .cap-title {
  color: var(--spot);
}

.cap:hover .arw {
  color: var(--spot);
  transform: translateX(4px);
}

.cap:hover .n > span {
  color: var(--spot);
}

.n {
  display: flex;
  align-items: center;
}

.n > span {
  font-family: var(--disp);
  font-weight: 900;
  font-size: 28px;
  letter-spacing: -0.04em;
  color: var(--line2);
  transition: color 0.12s ease;
  font-variant-numeric: tabular-nums;
}

.cap-title-col {
  min-width: 0;
}

.cap-title {
  font-family: var(--disp);
  font-weight: 800;
  font-size: 17px;
  letter-spacing: -0.02em;
  color: var(--ink);
  margin: 0;
  display: flex;
  align-items: center;
  gap: 8px;
  transition: color 0.12s ease;
}

.arw {
  font-family: var(--body);
  font-size: 14px;
  color: var(--faint);
  transition: all 0.12s ease;
  display: inline-block;
}

.cap-desc-col {
  min-width: 0;
}

.cap-desc {
  font-family: var(--body);
  font-size: 14px;
  line-height: 1.6;
  color: var(--dim);
  margin: 0;
}

/* Responsive */
@media (max-width: 860px) {
  .cap {
    grid-template-columns: 50px 1fr;
    gap: 6px 18px;
    align-items: start;
    padding: 16px var(--gut);
  }
  .cap-desc-col {
    grid-column: 2;
  }
  .n > span {
    font-size: 22px;
  }
  .cap-title {
    font-size: 15.5px;
  }
  .cap-desc {
    font-size: 13px;
  }
}
</style>
