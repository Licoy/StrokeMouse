<script setup lang="ts">
import GestureStrokeCanvas from './GestureStrokeCanvas.vue'
import { GESTURE_PATHS } from '../gesturePaths'

export interface GestureRow {
  /** Key into GESTURE_PATHS for canvas animation */
  path: string
  /** @deprecated unused — canvas only */
  stroke?: string
  action: string
  note?: string
}

defineProps<{
  heading?: string
  subheading?: string
  columns: { stroke: string; action: string; note?: string }
  rows: GestureRow[]
}>()
</script>

<template>
  <section class="gesture-table">
    <header v-if="heading || subheading" class="gesture-table__header">
      <p v-if="subheading" class="gesture-table__kicker">{{ subheading }}</p>
      <h2 v-if="heading" class="gesture-table__heading">{{ heading }}</h2>
    </header>
    <div class="gesture-table__wrap">
      <table>
        <thead>
          <tr>
            <th class="col-preview">{{ columns.stroke }}</th>
            <th>{{ columns.action }}</th>
            <th v-if="columns.note">{{ columns.note }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, i) in rows" :key="i">
            <td class="stroke-cell">
              <GestureStrokeCanvas
                v-if="GESTURE_PATHS[row.path]"
                :points="GESTURE_PATHS[row.path]"
                :delay-ms="i * 180"
              />
            </td>
            <td class="action-cell">{{ row.action }}</td>
            <td v-if="columns.note" class="note">{{ row.note || '—' }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<style scoped>
.gesture-table {
  margin: 3rem 0 2rem;
}

.gesture-table__header {
  margin-bottom: 1.25rem;
}

.gesture-table__kicker {
  margin: 0 0 0.4rem;
  font-family: var(--sm-font-mono);
  font-size: 12px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--sm-accent);
}

.gesture-table__heading {
  margin: 0;
  font-family: var(--sm-font-mono);
  font-size: 1.45rem;
  font-weight: 600;
  color: var(--sm-text);
}

/* Flush table — no empty pocket above/below cells */
.gesture-table__wrap {
  margin: 0;
  padding: 0;
  border-radius: 12px;
  overflow: hidden;
  background: var(--sm-panel);
  box-shadow: inset 0 0 0 1px var(--sm-border);
  line-height: normal;
}

table {
  width: 100%;
  margin: 0;
  border-collapse: collapse;
  border-spacing: 0;
  font-size: 0.92rem;
}

th,
td {
  text-align: left;
  margin: 0;
  border: none;
  border-bottom: 1px solid var(--sm-border);
  vertical-align: middle;
}

th {
  padding: 0.7rem 1rem;
  font-family: var(--sm-font-mono);
  font-size: 0.75rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--sm-accent);
  background: color-mix(in srgb, var(--sm-accent) 12%, var(--sm-bg-elevated));
}

th.col-preview {
  width: 5.5rem;
  text-align: center;
}

td {
  padding: 0.55rem 1rem;
  background: transparent;
}

tr:last-child td {
  border-bottom: none;
}

.stroke-cell {
  width: 5.5rem;
  text-align: center;
  padding: 0.45rem 0.65rem !important;
}

.stroke-cell :deep(.stroke-canvas) {
  margin: 0 auto;
}

.action-cell {
  color: var(--sm-text);
}

.note {
  color: var(--sm-text-muted);
  font-size: 0.88rem;
  white-space: nowrap;
}

@media (max-width: 640px) {
  th:nth-child(3),
  td:nth-child(3) {
    display: none;
  }
}
</style>
