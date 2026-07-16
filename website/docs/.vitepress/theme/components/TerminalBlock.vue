<script setup lang="ts">
defineProps<{
  title?: string
  lines: string[]
  prompt?: string
}>()
</script>

<template>
  <section class="term">
    <div class="term__bar">
      <span class="dot red" /><span class="dot yellow" /><span class="dot green" />
      <span class="term__title">{{ title || 'terminal' }}</span>
    </div>
    <div class="term__body">
      <p v-for="(line, i) in lines" :key="i" class="term__line">
        <span v-if="prompt !== ''" class="term__prompt">{{ prompt ?? '$' }}</span>
        <span class="term__text">{{ line }}</span>
      </p>
    </div>
  </section>
</template>

<style scoped>
.term {
  margin: 2rem 0;
  border: none;
  border-radius: var(--sm-radius);
  background: var(--sm-panel);
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
  overflow: hidden;
  box-shadow: var(--sm-ring), var(--sm-shadow);
}

.term__bar {
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

.term__title {
  margin-left: 0.45rem;
  font-family: var(--sm-font-mono);
  font-size: 11px;
  color: var(--sm-text-faint);
  letter-spacing: 0.04em;
}

.term__body {
  margin: 0;
  padding: 1.05rem 1.15rem 1.2rem;
  font-family: var(--sm-font-mono);
  font-size: 13px;
  line-height: 1.75;
  color: var(--sm-text);
  overflow-x: auto;
  scrollbar-width: thin;
  scrollbar-color: color-mix(in srgb, var(--sm-text-faint) 50%, transparent) transparent;
}

.term__line {
  margin: 0;
  display: flex;
  gap: 0.55rem;
  align-items: baseline;
}

.term__prompt {
  color: var(--sm-accent);
  user-select: none;
  flex-shrink: 0;
}

.term__text {
  color: var(--sm-text);
  word-break: break-word;
}
</style>
