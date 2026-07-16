/** Shared demo set for homepage HUD + default gesture table */

export interface GestureDemo {
  path: string
  nameZh: string
  nameEn: string
  /** Simulated match score 0–1 */
  score: number
}

export const DEFAULT_GESTURE_DEMOS: GestureDemo[] = [
  { path: 'up', nameZh: 'Mission Control', nameEn: 'Mission Control', score: 0.96 },
  { path: 'down', nameZh: '应用程序窗口', nameEn: 'Application Windows', score: 0.94 },
  { path: 'downLeft', nameZh: '最小化窗口', nameEn: 'Minimize Window', score: 0.93 },
  { path: 'downRight', nameZh: '关闭窗口', nameEn: 'Close Window', score: 0.95 },
  { path: 'upRight', nameZh: '打开 Safari', nameEn: 'Open Safari', score: 0.92 },
  { path: 'rightLeft', nameZh: '播放 / 暂停', nameEn: 'Play / Pause', score: 0.91 },
  { path: 'upLeft', nameZh: '打开 GitHub', nameEn: 'Open GitHub', score: 0.94 },
]

export function toastMatchedText(name: string, score: number, isZh: boolean): string {
  const pct = Math.round(score * 100)
  // Icon is shown separately — no leading ✓ (avoids double checkmark)
  return isZh ? `${name}  (匹配度 ${pct}%)` : `${name}  (${pct}%)`
}
