<script setup lang="ts">
import { PhArrowUpRight } from '@phosphor-icons/vue'

withDefaults(
  defineProps<{
    href: string
    variant?: 'primary' | 'ghost'
    arrow?: boolean
  }>(),
  {
    variant: 'primary',
    arrow: true,
  },
)
</script>

<template>
  <a
    class="sm-btn"
    :class="variant === 'primary' ? 'sm-btn--primary' : 'sm-btn--ghost'"
    :href="href"
  >
    <span><slot /></span>
    <span v-if="arrow && variant === 'primary'" class="sm-btn__icon" aria-hidden="true">
      <PhArrowUpRight :size="14" weight="bold" />
    </span>
  </a>
</template>
