/**
 * Gusts: the wind near the ground is never steady. Eddies shed by the ground and, under a storm,
 * the downdraught's outflow bring it in surges every half a minute or so that build over seconds
 * and ease off again (a storm's gust factor, peak over mean, is about 1.5–2). Each surge drives
 * the rain slantwise and, carrying the air the rain falls through, a heavier burst of it.
 *
 * A pure function of real time, so the rain gusts even with the clock stopped: smooth value
 * noise, its quiet stretches cut off so that gusts stand apart, plus a little flutter within each.
 */

import { lerp, smoothstep, type Vec2 } from './math'

/** Seconds between the noise's lattice points: gusts come every 20 to 60 s. */
const gustSpacing = 16
/** Of the noise's range, where a surge begins and where it is at its height. */
const surge = [0.4, 0.85] as const
/** The flutter within a gust, seconds between lattice points, and its share of it. */
const flutterSpacing = 2.5
const flutter = 0.25
/**
 * The breeze, m/s (x = east, z = north), and how much stronger it blows in a gust: a calm light
 * rain only sways, a storm's outflow blows hard and leans the rain far over.
 */
const breezeHeading: Vec2 = [0.94, 0.35]
const breeze = { calm: 0.85, storm: 3 }
const gustWind = { calm: 0.6, storm: 4.5 }
/** How far a gust turns the wind, radians at its height. */
const gustVeer = 0.25
/** How much a gust swells the rain rate: ±share about its mean, gently in light rain. */
const gustRain = { calm: 0.25, storm: 0.55 }

function hash(n: number) {
  let h = Math.imul(n ^ 0x2c1b3c6d, 0x297a2d39)
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b)
  return ((h ^ (h >>> 13)) >>> 0) / 4294967296
}

/** Smooth value noise in [0, 1) at `x` lattice units, C² between its lattice points. */
function valueNoise(x: number, salt: number) {
  const i = Math.floor(x)
  const f = x - i
  const w = f * f * f * (f * (f * 6 - 15) + 10)
  return lerp(hash(i * 7 + salt), hash((i + 1) * 7 + salt), w)
}

/** How far a gust is blowing `seconds` into the visit: 0 between them, 1 at the height of one. */
function gustAt(seconds: number) {
  const gust = smoothstep(surge[0], surge[1], valueNoise(seconds / gustSpacing, 1))
  return gust * (1 - flutter + flutter * valueNoise(seconds / flutterSpacing, 3))
}

export interface Gusts {
  /** The wind near the ground, m/s. */
  rainWind: Vec2
  /** What the gust makes of the rain rate, a multiplier. */
  rainGust: number
}

/** The wind and the rain's surges `seconds` into the visit, under a storm as fierce as `storm` at the eye. */
export function gusts(seconds: number, storm: number): Gusts {
  const gust = gustAt(seconds)
  const speed = lerp(breeze.calm, breeze.storm, storm) + gust * lerp(gustWind.calm, gustWind.storm, storm)
  const veer = gustVeer * gust
  const [x, z] = breezeHeading
  const c = Math.cos(veer)
  const s = Math.sin(veer)
  return {
    rainWind: [speed * (c * x - s * z), speed * (s * x + c * z)],
    rainGust: 1 + lerp(gustRain.calm, gustRain.storm, storm) * (2 * gust - 0.5),
  }
}
