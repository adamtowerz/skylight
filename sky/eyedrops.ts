/**
 * Drops on the eye. Lying in the rain, now and then a drop lands on the eye itself and sits on it
 * as a little lens until it slides off and drains away. How often follows the rain: drops larger
 * than a millimetre (smaller ones only wet the lashes) land on an eye's few square centimetres at
 * the Marshall–Palmer rate (`rainfall.ts`), so in light rain about one every twenty seconds and in
 * a downpour one a second, a few at a time. Each lands (spreading for a moment), sits,
 * slides slowly down across the view and, as it spreads thinner, fades.
 *
 * Which drops land, where and how large is drawn from a seeded generator, so a visit is never two
 * rains alike; `eyedrop.wgsl` refracts the frame through each.
 */

import { dropsLanding } from './rainfall'

/** Drops on the eye at once, at most: as many as `eyeDrops` holds (`uniforms.ts`). */
export const eyeDropSlots = 6
/**
 * The eye's exposed surface and the lashes that shed onto it, m², and the smallest drop that sits
 * on it as a lens, mm.
 */
const eyeArea = 2e-4
const smallestDrop = 1
/** How long a drop lies on the eye, s, and how long it takes to land, spreading out. */
const lingers = [3, 8] as const
const landing = 0.15
/** Its radius, as a share of the view's height (the eye sees it far out of focus, so large). */
const radius = [0.05, 0.12] as const
/** How fast it slides across the view, view heights per second, and how much it wanders aside. */
const slide = [0.006, 0.02] as const
const wander = 0.4
/** The share of its stay over which it drains away at the end. */
const draining = 0.45

interface Drop {
  x: number
  y: number
  radius: number
  born: number
  lingers: number
  /** Across the view and down it, uv per second. */
  vx: number
  vy: number
}

export interface EyeDrops {
  /** Lets drops land for `dt` seconds of rain at `rate` mm/h, `time` seconds into the visit; returns them as the GPU reads them. */
  advance(dt: number, time: number, rate: number): number[]
}

/** mulberry32: a small seeded generator. */
function generator(seed: number) {
  let state = seed >>> 0
  return () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = Math.imul(state ^ (state >>> 15), state | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const between = ([low, high]: readonly [number, number], t: number) => low + (high - low) * t

export function trackEyeDrops(seed = Date.now()): EyeDrops {
  const random = generator(seed)
  const drops: (Drop | undefined)[] = Array.from({ length: eyeDropSlots })

  function land(time: number): Drop {
    const size = random()
    return {
      // Anywhere on the view (uv, y down), seldom with its centre at the very top or bottom.
      x: random(),
      y: 0.05 + 0.9 * random(),
      radius: between(radius, size),
      born: time,
      lingers: between(lingers, random()),
      vx: wander * (random() - 0.5) * between(slide, size),
      vy: between(slide, size * random()),
    }
  }

  return {
    advance(dt, time, rate) {
      for (let slot = 0; slot < eyeDropSlots; slot++) {
        const drop = drops[slot]
        if (drop && time - drop.born > drop.lingers) drops[slot] = undefined
      }
      // Landings come as a Poisson process; one more than there are free slots runs off the lashes.
      const free = drops.indexOf(undefined)
      if (free >= 0 && random() < dropsLanding(rate, smallestDrop) * eyeArea * dt) drops[free] = land(time)
      const out: number[] = []
      for (const drop of drops) {
        if (!drop) {
          out.push(0, 0, 0, 0)
          continue
        }
        const age = time - drop.born
        const landed = Math.min(age / landing, 1)
        const drained = Math.min(Math.max((drop.lingers - age) / (draining * drop.lingers), 0), 1)
        // It spreads as it lands and a little more as it drains, thinning: a weaker lens.
        const spread = (0.7 + 0.3 * landed) * (1 + 0.25 * (1 - drained))
        out.push(drop.x + drop.vx * age, drop.y + drop.vy * age, drop.radius * spread, landed * drained * drained)
      }
      return out
    },
  }
}
