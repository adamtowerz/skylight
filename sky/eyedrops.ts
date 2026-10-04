/**
 * Drops on the eye. Lying in the rain, now and then a drop lands on the eye itself and sits on it
 * as a little lens until it slides off and drains away. How often follows the rain: drops larger
 * than a millimetre (smaller ones only wet the lashes) land on an eye's few square centimetres at
 * the Marshall–Palmer rate (`rainfall.ts`), so in light rain about one every twenty seconds and in
 * a downpour one a second, a few at a time.
 *
 * Each lands softly, spreading out for a moment and beading back, then sits pinned by its contact
 * line (contact angle hysteresis, de Gennes 1985, "Wetting: statics and dynamics") until its
 * weight overcomes the pinning, when the larger ones ease into a slow slide down the view; some
 * leave a short thin trail of water behind, the rest of the film they slid over. As it spreads
 * thinner it fades.
 *
 * Which drops land, where and how large is drawn from a generator seeded by the opening moment, and
 * the landings from the expected count so far rather than a draw per frame, so reloading one
 * `?hour=` shows the same drops at the same moments; `eyedrop.wgsl` refracts the frame through each.
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
/** How long a drop lies on the eye, s, and how long it takes to land, spreading out and beading back. */
const lingers = [3, 8] as const
const landing = 0.3
/** How far out it spreads as it lands, and how flat (a weaker lens) it starts. */
const landingSpread = 0.08
const landingFlat = 0.5
/** Its radius, as a share of the view's height (the eye sees it far out of focus, so large). */
const radius = [0.05, 0.12] as const
/** How long its contact line holds it before it slides, s, and how quickly it then gets going. */
const pinned = [0.5, 2.5] as const
const slipping = 0.6
/**
 * How fast it slides down the view, view heights per second, and how much it wanders aside; the
 * smallest drops' weight never overcomes the pinning.
 */
const slide = [0.008, 0.03] as const
const wander = 0.4
const slides = 0.3
/** The share of sliding drops that leave a trail, and its longest, in the drop's radii. */
const trails = 0.5
const trailLength = 1.5
/** The share of its stay over which it drains away at the end. */
const draining = 0.45

interface Drop {
  x: number
  y: number
  radius: number
  born: number
  lingers: number
  pinned: number
  /** Across the view and down it once sliding, uv per second. */
  vx: number
  vy: number
  trails: boolean
}

export interface EyeDrops {
  /** Lets drops land for `dt` seconds of rain at `rate` mm/h, `time` seconds into the visit; returns them as the GPU reads them. */
  advance(dt: number, time: number, rate: number): { eyeDrops: number[]; eyeDropShapes: number[] }
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

/** How far a drop has slid `t` seconds after it began to, at full speed 1: it eases into the slide. */
const slid = (t: number) => (t > 0 ? t - slipping * (1 - Math.exp(-t / slipping)) : 0)

export function trackEyeDrops(seed: number): EyeDrops {
  const random = generator(Math.round(seed * 3600))
  const drops: (Drop | undefined)[] = Array.from({ length: eyeDropSlots })
  // Landings expected so far, and the count at which the next one comes (exponential gaps).
  let expected = 0
  let next = -Math.log(1 - random())

  function land(time: number): Drop {
    const size = random()
    const sliding = size > slides
    return {
      // Anywhere on the view (uv, y down), seldom with its centre at the very top or bottom.
      x: random(),
      y: 0.05 + 0.9 * random(),
      radius: between(radius, size),
      born: time,
      lingers: between(lingers, random()),
      pinned: between(pinned, random()),
      vx: sliding ? wander * (random() - 0.5) * between(slide, size) : 0,
      vy: sliding ? between(slide, size * random()) : 0,
      trails: sliding && random() < trails,
    }
  }

  return {
    advance(dt, time, rate) {
      for (let slot = 0; slot < eyeDropSlots; slot++) {
        const drop = drops[slot]
        if (drop && time - drop.born > drop.lingers) drops[slot] = undefined
      }
      // Landings come as a Poisson process; one more than there are free slots runs off the lashes.
      expected += dropsLanding(rate, smallestDrop) * eyeArea * dt
      if (expected >= next) {
        expected = 0
        next = -Math.log(1 - random())
        // Drawn whether or not it stays, so the draws keep in step however full the eye is.
        const fresh = land(time)
        const free = drops.indexOf(undefined)
        if (free >= 0) drops[free] = fresh
      }
      const eyeDrops: number[] = []
      const eyeDropShapes: number[] = []
      for (const drop of drops) {
        if (!drop) {
          eyeDrops.push(0, 0, 0, 0)
          eyeDropShapes.push(0, 0, 0, 0)
          continue
        }
        const age = time - drop.born
        const landed = Math.min(age / landing, 1)
        const drained = Math.min(Math.max((drop.lingers - age) / (draining * drop.lingers), 0), 1)
        // It lands flat, spreading out a little, and beads back into a stronger lens; it spreads
        // again as it drains away.
        const spread = (0.8 + 0.2 * landed + landingSpread * Math.sin(Math.PI * landed)) * (1 + 0.25 * (1 - drained))
        const beaded = landingFlat + (1 - landingFlat) * landed * landed
        const along = slid(age - drop.pinned)
        const [vx, vy] = [drop.vx * along, drop.vy * along]
        // Its trail runs back the way it slid, no further than it has gone, in view heights.
        const trail = drop.trails ? Math.min(1, (trailLength * drop.radius) / Math.max(Math.hypot(vx, vy), 1e-6)) : 0
        eyeDrops.push(drop.x + vx, drop.y + vy, drop.radius * spread, landed * drained * drained)
        eyeDropShapes.push(-vx * trail, -vy * trail, drained, beaded)
      }
      return { eyeDrops, eyeDropShapes }
    },
  }
}
