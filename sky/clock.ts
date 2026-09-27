/**
 * Simulated time of day. Time lingers through sunrise and sunset (the moments worth lying on
 * the grass for) and hurries through midday and deep night: a full day takes about six minutes.
 */

import { lerp, radians, smoothstep } from './math'
import { sunElevation } from './celestial'

/** Real seconds per simulated hour, near the horizon and away from it. */
const lingerSecondsPerHour = 45
const hurrySecondsPerHour = 9
/** How quickly a keyboard nudge eases in, per second. */
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
  togglePause(): void
}

export interface ClockOptions {
  hour?: number
  /** Multiplier on the natural pace; 0 freezes time. */
  speed?: number
}

/** 1 while the sun is between −12° and +15° (twilight and golden hour), 0 well outside it. */
function lingering(hour: number) {
  const elevation = sunElevation(hour)
  return smoothstep(radians(-18), radians(-12), elevation) * (1 - smoothstep(radians(15), radians(22), elevation))
}

const secondsPerHour = (hour: number) => lerp(hurrySecondsPerHour, lingerSecondsPerHour, lingering(hour))

/** Real seconds from midnight to each 1/`stepsPerHour` of a day, at the natural pace. */
const stepsPerHour = 12
const timeline = [0]
for (let step = 0; step < 24 * stepsPerHour; step++) {
  timeline.push(timeline[step] + secondsPerHour((step + 0.5) / stepsPerHour) / stepsPerHour)
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

export function createClock({ hour = 17.6, speed = 1 }: ClockOptions = {}): Clock {
  let hours = hour
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
    togglePause() {
      paused = !paused
    },
  }
}
