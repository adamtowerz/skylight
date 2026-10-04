/**
 * Simulated time of day. Time lingers through sunrise and sunset (the moments worth lying on
 * the grass for) and hurries through midday and deep night: a full day takes about six minutes.
 * It lingers too while a thunderstorm passes (`stormLingers`), at least `stormSecondsPerHour` whatever
 * the hour, so a storm takes a few minutes to pass rather than seconds, mid-afternoon or at dusk.
 */

import { lerp, radians, smoothstep } from './math'
import { sunElevation } from './celestial'
import { stormLingers } from './weather'

/** Real seconds per simulated hour, near the horizon and away from it. */
const lingerSecondsPerHour = 45
const hurrySecondsPerHour = 9
/** Real seconds per simulated hour at least, under a storm: its 1–3 h take some 2–6 minutes. */
const stormSecondsPerHour = 120
/** How quickly a nudge or scrub eases in, per second. */
const nudgeRate = 4

export interface Clock {
  /** Simulated hours since midnight of day zero; keeps counting across days. */
  readonly hours: number
  /** Hour of the current day, in [0, 24). */
  readonly hour: number
  readonly paused: boolean
  advance(dt: number): void
  /** Eases the clock forward or back by `hours`. */
  nudge(hours: number): void
  /**
   * Eases the clock forward or back by `seconds` at its natural pace, so a steady scroll
   * lingers through twilight just as the clock does.
   */
  scrub(seconds: number): void
  togglePause(): void
}

export interface ClockOptions {
  /** Simulated hours since midnight of day zero to start at. */
  hours: number
  /** Multiplier on the natural pace; 0 freezes time. */
  speed?: number
}

/** 1 while the sun is between −12° and +15° (twilight and golden hour), 0 well outside it. */
function lingering(hour: number) {
  const elevation = sunElevation(hour)
  return smoothstep(radians(-18), radians(-12), elevation) * (1 - smoothstep(radians(15), radians(22), elevation))
}

const naturalSecondsPerHour = (hour: number) => lerp(hurrySecondsPerHour, lingerSecondsPerHour, lingering(hour))

/** How many real seconds per simulated hour a storm adds to the natural pace at `hours`. */
function stormSeconds(hours: number) {
  const natural = naturalSecondsPerHour(hours)
  return stormLingers(hours).lingering * Math.max(stormSecondsPerHour - natural, 0)
}

/** Real seconds per simulated hour at `hours`: the natural pace, slowed further under a storm. */
const secondsPerHour = (hours: number) => naturalSecondsPerHour(hours) + stormSeconds(hours)

/** Real seconds from midnight to each 1/`stepsPerHour` of a day, at the natural pace. */
const stepsPerHour = 12
const timeline = [0]
for (let step = 0; step < 24 * stepsPerHour; step++) {
  timeline.push(timeline[step] + naturalSecondsPerHour((step + 0.5) / stepsPerHour) / stepsPerHour)
}
const secondsPerDay = timeline[timeline.length - 1]

/**
 * Real seconds the natural pace takes to reach `hours` (simulated, since midnight of day zero).
 * Motion that should look steady on screen, like drifting clouds, runs on this instead of on
 * hours: it neither races through noon nor stalls at sunset, yet stays a pure function of
 * simulated time, so scrubbing the clock scrubs it too.
 */
export function naturalSeconds(hours: number) {
  const days = Math.floor(hours / 24)
  const step = (hours - days * 24) * stepsPerHour
  const index = Math.min(Math.floor(step), timeline.length - 2)
  return days * secondsPerDay + lerp(timeline[index], timeline[index + 1], step - index)
}

/** Steps of the integral of a storm's lingering (Simpson's rule, even). */
const lingeringSteps = 32

/**
 * Real seconds the clock takes to reach `hours`: the natural pace's (`naturalSeconds`) plus the
 * time it has lingered under the day's storm so far. The storm's own motions (its scud, churn and
 * curtains) run on this, so they keep their pace on screen while the clock slows; they are gone by
 * the day's end, where this jumps back to the natural pace's.
 */
export function clockSeconds(hours: number) {
  const { since } = stormLingers(hours)
  const span = hours - since
  if (span <= 0) return naturalSeconds(hours)
  const step = span / lingeringSteps
  let lingered = 0
  for (let i = 0; i <= lingeringSteps; i++) {
    const at = since + i * step
    const weight = i === 0 || i === lingeringSteps ? 1 : i % 2 ? 4 : 2
    lingered += weight * stormSeconds(at)
  }
  return naturalSeconds(hours) + (lingered * step) / 3
}

export function createClock({ hours: start, speed = 1 }: ClockOptions): Clock {
  let hours = start
  let pendingNudge = 0
  let paused = false

  return {
    get hours() {
      return hours
    },
    get hour() {
      return ((hours % 24) + 24) % 24
    },
    get paused() {
      return paused
    },
    advance(dt) {
      const eased = pendingNudge * (1 - Math.exp(-nudgeRate * dt))
      pendingNudge -= eased
      hours += eased
      if (paused) return
      hours += (dt * speed) / secondsPerHour(hours)
    },
    nudge(delta) {
      pendingNudge += delta
    },
    scrub(seconds) {
      pendingNudge += seconds / secondsPerHour(hours + pendingNudge)
    },
    togglePause() {
      paused = !paused
    },
  }
}
