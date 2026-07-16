/** Unit-space free-path templates (y-up), mirrored from PathTemplates.swift */

export type Pt = { x: number; y: number }

function line(from: Pt, to: Pt, samples = 24): Pt[] {
  return Array.from({ length: samples }, (_, i) => {
    const t = i / (samples - 1)
    return {
      x: from.x + (to.x - from.x) * t,
      y: from.y + (to.y - from.y) * t,
    }
  })
}

function polyline(corners: Pt[], samplesPerSegment = 12): Pt[] {
  if (corners.length < 2) return corners.slice()
  const points: Pt[] = []
  for (let i = 0; i < corners.length - 1; i++) {
    const a = corners[i]
    const b = corners[i + 1]
    const start = i === 0 ? 0 : 1
    for (let s = start; s <= samplesPerSegment; s++) {
      const t = s / samplesPerSegment
      points.push({
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
      })
    }
  }
  return points
}

export const GESTURE_PATHS: Record<string, Pt[]> = {
  up: line({ x: 0.5, y: 0.1 }, { x: 0.5, y: 0.9 }),
  down: line({ x: 0.5, y: 0.9 }, { x: 0.5, y: 0.1 }),
  downLeft: polyline([
    { x: 0.5, y: 0.9 },
    { x: 0.5, y: 0.4 },
    { x: 0.1, y: 0.4 },
  ]),
  downRight: polyline([
    { x: 0.5, y: 0.9 },
    { x: 0.5, y: 0.4 },
    { x: 0.9, y: 0.4 },
  ]),
  upRight: polyline([
    { x: 0.5, y: 0.1 },
    { x: 0.5, y: 0.6 },
    { x: 0.9, y: 0.6 },
  ]),
  rightLeft: polyline([
    { x: 0.1, y: 0.5 },
    { x: 0.9, y: 0.5 },
    { x: 0.1, y: 0.5 },
  ]),
  upLeft: polyline([
    { x: 0.5, y: 0.1 },
    { x: 0.5, y: 0.6 },
    { x: 0.1, y: 0.6 },
  ]),
}
