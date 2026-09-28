/**
 * Known-good opening moments. Each load without `?hour=` starts at one of these, so no two
 * visits open on the same sky. Hours count across days because the weather is a pure function
 * of simulated time: the day picks the cloudscape, the hour the light, and each opens a little
 * before its best light so the sky has somewhere to go.
 */

import type { Params } from './controls'

export interface Seed {
  /** Simulated hours since midnight of day zero. */
  hours: number
  /** The mood of the nearest twilight (see `moodCycle`). */
  mood: number
}

export const seeds: readonly Seed[] = [
  { hours: 18.3, mood: 2 }, // ember heaps catching the last gold
  { hours: 24 + 18.5, mood: 0 }, // a golden bank overhead that burns rose
  { hours: 48 + 18.4, mood: 1 }, // violet dusk under long cirrus streaks
  { hours: 72 + 5.3, mood: 1 }, // sunrise: pink heaps turning cream on blue
  { hours: 96 + 18.2, mood: 3 }, // a clear evening with scattered fair-weather heaps
  { hours: 120 + 17.9, mood: 0 }, // a quiet afternoon settling into golden haze
  { hours: 144 + 18.4, mood: 2 }, // a towering bank that turns ember red
]

/**
 * Where the sky opens: `?hour=` (and `?mood=`) when given, else `?seed=n`, else a random seed.
 */
export function openingMoment({ hour, mood, seed }: Params): Seed {
  if (hour !== undefined) return { hours: hour, mood: mood ?? 0 }
  const index = seed ?? Math.floor(Math.random() * seeds.length)
  const chosen = seeds[((index % seeds.length) + seeds.length) % seeds.length]
  return { hours: chosen.hours, mood: mood ?? chosen.mood }
}
