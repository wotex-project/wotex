import type { MetricSeries } from "$lib/islands/canvas-model.ts"

/** Missing samples stay null. Dotted bridges are visual annotations only. */
export const metricGeometry = (
  series: MetricSeries[],
  mark: "line" | "point" | "area" = "line",
) => {
  const xs = series.flatMap((s) => s.points.map((p) => p[0]))
  const ys = series.flatMap((s) => s.points.flatMap((p) => (p[1] === null ? [] : [p[1]])))

  const domain = (values: number[]) => {
    const lo = Math.min(...values)
    const hi = Math.max(...values)
    if (!values.length) {
      return [0, 1]
    }
    const pad = Math.max(Math.abs(lo) * 0.05, 1)
    return lo === hi ? [lo - pad, hi + pad] : [lo, hi]
  }

  const [x0, x1] = domain(xs)
  const [y0, y1] = domain(mark === "area" ? [...ys, 0] : ys)

  const sx = (x: number) => 42 + ((x - x0) / (x1 - x0)) * 270

  const sy = (y: number) => 12 + ((y1 - y) / (y1 - y0)) * 112

  const xy = (p: [number, number]) => `${sx(p[0]).toFixed(2)},${sy(p[1]).toFixed(2)}`

  return {
    available: ys.length > 0,
    missing: series.reduce((n, s) => n + s.points.filter((p) => p[1] === null).length, 0),
    xTicks: [x0, (x0 + x1) / 2, x1].map((v) => ({
      value: v,
      x: sx(v),
    })),
    yTicks: [y0, (y0 + y1) / 2, y1].map((v) => ({
      value: v,
      y: sy(v),
    })),
    series: series.map((s) => {
      const segments: string[] = []
      const bridges: string[] = []
      const areas: string[] = []
      const dots: {
        x: number
        y: number
      }[] = []
      let segment: [number, number][] = []
      let previous: [number, number] | null = null
      let gap = false

      const flush = () => {
        if (!segment.length) {
          return
        }
        const points = segment.map(xy).join(" ")
        segments.push(points)
        areas.push(`${xy([segment[0][0], 0])} ${points} ${xy([segment[segment.length - 1][0], 0])}`)
      }

      for (const [x, y] of s.points) {
        if (y === null) {
          flush()
          segment = []
          gap = true
        } else {
          const point: [number, number] = [x, y]
          if (gap && previous) {
            bridges.push(`${xy(previous)} ${xy(point)}`)
          }
          segment.push(point)
          previous = point
          gap = false
          dots.push({
            x: sx(x),
            y: sy(y),
          })
        }
      }
      flush()
      return {
        name: s.name,
        segments,
        bridges,
        areas,
        dots,
      }
    }),
  }
}

export const metricLabel = (value: number): string => {
  return new Intl.NumberFormat("en", {
    maximumSignificantDigits: 3,
  }).format(value)
}
