/**
 * A blue-noise mask for the clouds' jitter, generated at startup by void and cluster (Ulichney
 * 1993, "The void-and-cluster method for dither array generation"): every pixel of a toroidal
 * 64 × 64 tile gets a rank, and every threshold of the ranks leaves points as evenly spread as
 * they can be, so neighbouring pixels always take jitters far apart. Its error then lies at high
 * spatial frequencies, which a pixel's neighbours average away and the eye barely sees, rather
 * than in the clumps white noise leaves. A few tens of milliseconds of CPU, and no asset to ship.
 */

/** Side of the tile, px. */
export const blueNoiseSize = 64
export const blueNoiseFormat: GPUTextureFormat = 'r8unorm'

/** Where shaders that include `bluenoise.wgsl` read the mask. */
export const blueNoiseEntry = (mask: GPUTextureView): GPUBindGroupEntry => ({ binding: 9, resource: mask })

/** Spread of the energy each point radiates, px (Ulichney's 1.5). */
const sigma = 1.5
/** The energy is cut off where it has faded to nothing. */
const reach = 6
/** Share of the tile set in the initial pattern. */
const initialShare = 0.1

/** Mulberry32: a small seeded generator, so every load draws the same mask. */
function random(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/** The mask, one byte per pixel, row-major: each pixel's rank scaled to [0, 256). */
export function blueNoise(): Uint8Array<ArrayBuffer> {
  const size = blueNoiseSize
  const count = size * size
  const kernel: number[] = []
  for (let dy = -reach; dy <= reach; dy++) {
    for (let dx = -reach; dx <= reach; dx++) kernel.push(Math.exp(-(dx * dx + dy * dy) / (2 * sigma * sigma)))
  }
  // How crowded each pixel is by the points around it, over the torus.
  const energy = new Float64Array(count)
  const points = new Uint8Array(count)
  const toggle = (pixel: number, on: boolean) => {
    points[pixel] = on ? 1 : 0
    const x = pixel % size
    const y = (pixel - x) / size
    let k = 0
    for (let dy = -reach; dy <= reach; dy++) {
      const row = ((y + dy + size) % size) * size
      for (let dx = -reach; dx <= reach; dx++) {
        energy[row + ((x + dx + size) % size)] += on ? kernel[k] : -kernel[k]
        k++
      }
    }
  }
  // The most crowded point (the tightest cluster), or the emptiest gap (the largest void).
  const tightestCluster = () => {
    let best = -1
    for (let i = 0; i < count; i++) if (points[i] && (best < 0 || energy[i] > energy[best])) best = i
    return best
  }
  const largestVoid = () => {
    let best = -1
    for (let i = 0; i < count; i++) if (!points[i] && (best < 0 || energy[i] < energy[best])) best = i
    return best
  }

  // A random pattern, relaxed by moving its most crowded point to the emptiest gap until the
  // point moved would come straight back.
  const next = random(1)
  let initial = 0
  while (initial < Math.round(initialShare * count)) {
    const pixel = Math.floor(next() * count)
    if (!points[pixel]) {
      toggle(pixel, true)
      initial++
    }
  }
  for (;;) {
    const cluster = tightestCluster()
    toggle(cluster, false)
    const gap = largestVoid()
    toggle(gap, true)
    if (gap === cluster) break
  }
  const prototype = points.slice()
  const prototypeEnergy = energy.slice()

  // Ranks below the pattern: take away the tightest cluster, one at a time.
  const rank = new Uint32Array(count)
  for (let ones = initial; ones > 0; ) {
    const cluster = tightestCluster()
    toggle(cluster, false)
    rank[cluster] = --ones
  }
  // Ranks above it: from the pattern again, fill the largest void, one at a time.
  points.set(prototype)
  energy.set(prototypeEnergy)
  for (let ones = initial; ones < count; ones++) {
    const gap = largestVoid()
    toggle(gap, true)
    rank[gap] = ones
  }
  return Uint8Array.from(rank, (r) => Math.floor((r * 256) / count))
}
