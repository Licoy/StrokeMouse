<script setup lang="ts">
withDefaults(
  defineProps<{
    title: string
    body: string
    variant?: 'info' | 'warn'
  }>(),
  { variant: 'info' },
)
</script>

<template>
  <aside class="callout" :class="`callout--${variant}`">
    <div class="callout__label">
      <span class="callout__mark">{{ variant === 'warn' ? '!' : '>' }}</span>
      {{ title }}
    </div>
    <p class="callout__body">{{ body }}</p>
  </aside>
</template>

<style scoped>
.callout {
  margin: 2.5rem 0;
  padding: 1.2rem 1.3rem;
  border-radius: var(--sm-radius);
  border: none;
  background: var(--sm-panel);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  box-shadow: var(--sm-ring);
}

.callout--info {
  box-shadow:
    var(--sm-ring),
    inset 3px 0 0 var(--sm-accent);
}

.callout--warn {
  box-shadow:
    0 0 0 1px color-mix(in srgb, var(--sm-amber) 35%, transparent),
    inset 3px 0 0 var(--sm-amber);
}

.callout__label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-family: var(--sm-font-mono);
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--sm-accent);
  margin-bottom: 0.45rem;
}

.callout--warn .callout__label {
  color: var(--sm-amber);
}

.callout__mark {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.1rem;
  height: 1.1rem;
  border-radius: 3px;
  background: var(--sm-accent-glow);
  font-size: 11px;
}

.callout--warn .callout__mark {
  background: color-mix(in srgb, var(--sm-amber) 15%, transparent);
}

.callout__body {
  margin: 0;
  font-size: 0.95rem;
  line-height: 1.6;
  color: var(--sm-text-muted);
}
</style>
