<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'
import GestureTable from './GestureTable.vue'

const { lang } = useData()
const isZh = computed(() => !lang.value || lang.value.startsWith('zh'))

const columns = computed(() =>
  isZh.value
    ? { stroke: '轨迹', action: '动作', note: '触发键' }
    : { stroke: 'Stroke', action: 'Action', note: 'Trigger' },
)

const rows = computed(() =>
  isZh.value
    ? [
        { path: 'up', action: 'Mission Control（⌃↑）', note: '右键' },
        { path: 'down', action: '应用程序窗口（⌃↓）', note: '右键' },
        { path: 'downLeft', action: '最小化窗口', note: '右键' },
        { path: 'downRight', action: '关闭窗口', note: '右键' },
        { path: 'upRight', action: '打开 Safari', note: '右键' },
        { path: 'rightLeft', action: '播放 / 暂停', note: '右键' },
        { path: 'upLeft', action: '打开 GitHub', note: '右键' },
      ]
    : [
        { path: 'up', action: 'Mission Control (⌃↑)', note: 'Right button' },
        { path: 'down', action: 'Application windows (⌃↓)', note: 'Right button' },
        { path: 'downLeft', action: 'Minimize window', note: 'Right button' },
        { path: 'downRight', action: 'Close window', note: 'Right button' },
        { path: 'upRight', action: 'Open Safari', note: 'Right button' },
        { path: 'rightLeft', action: 'Play / Pause', note: 'Right button' },
        { path: 'upLeft', action: 'Open GitHub', note: 'Right button' },
      ],
)

defineProps<{
  heading?: string
  subheading?: string
}>()
</script>

<template>
  <GestureTable
    :heading="heading"
    :subheading="subheading"
    :columns="columns"
    :rows="rows"
  />
</template>
