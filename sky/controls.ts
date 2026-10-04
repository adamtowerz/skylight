/**
 * Invisible controls. URL parameters set the scene up (`?hour=18.4&speed=0&mood=2`, or
 * `?seed=3` for one of the opening moments), and any kind of weather can be held at a value over
 * the timeline (`?fog=0.8&haze=0.5&storm=1`, each 0 → 1); scrolling (or dragging and flicking on touch screens) winds
 * time back and forth, ←/→ nudge it by a quarter hour, space pauses, and the pointer adds a
 * touch of parallax.
 */

import type { Camera } from './camera'
import type { Clock } from './clock'
import { weatherKinds, type HeldWeather } from './weather'

const nudgeHours = 0.25
/** Natural seconds of clock per pixel scrolled: a wheel notch is a few minutes at dusk, a swipe an hour. */
const scrubSecondsPerPixel = 0.02
/** Pixels per line, for wheels that scroll by lines. */
const pixelsPerLine = 16
/** A drag on a touch screen winds further than a wheel: a phone is short, and a thumb's swipe is all it gets. */
const touchGain = 4
/** A flick keeps winding for as long as its speed would carry it in this many seconds, eased out by the clock. */
const flickCarrySeconds = 0.3
/** A drag held still this long before lifting is a placement, not a flick. */
const flickStaleMs = 100

export interface Params {
  hour?: number
  speed?: number
  mood?: number
  seed?: number
  /** Weather held at these values whatever the timeline says. */
  weather: HeldWeather
}

function numberParam(search: URLSearchParams, name: string) {
  const raw = search.get(name)
  const value = raw === null ? NaN : Number(raw)
  return Number.isFinite(value) ? value : undefined
}

/** Every kind of weather given a value, e.g. `?fog=0.8`. */
function heldWeather(search: URLSearchParams) {
  const held: HeldWeather = {}
  for (const kind of weatherKinds) {
    const value = numberParam(search, kind)
    if (value !== undefined) held[kind] = value
  }
  return held
}

export function readParams(query: string): Params {
  const search = new URLSearchParams(query)
  const integer = (name: string) => {
    const value = numberParam(search, name)
    return value === undefined ? undefined : Math.round(value)
  }
  return {
    hour: numberParam(search, 'hour'),
    speed: numberParam(search, 'speed'),
    mood: integer('mood'),
    seed: integer('seed'),
    weather: heldWeather(search),
  }
}

/** Binds keyboard and pointer input; returns the unbind function. */
export function bindControls(target: Window, clock: Clock, camera: Camera): () => void {
  function onKeyDown(event: KeyboardEvent) {
    if (event.key === 'ArrowLeft') clock.nudge(-nudgeHours)
    else if (event.key === 'ArrowRight') clock.nudge(nudgeHours)
    else if (event.key === ' ') clock.togglePause()
    else return
    event.preventDefault()
  }

  function onPointerMove(event: PointerEvent) {
    camera.point((event.clientX / target.innerWidth) * 2 - 1, (event.clientY / target.innerHeight) * 2 - 1)
  }

  // Scrolling down (content moving up) runs time forward, like scrolling down a timeline.
  const scrub = (pixels: number) => clock.scrub(pixels * scrubSecondsPerPixel)

  function onWheel(event: WheelEvent) {
    const unit = [1, pixelsPerLine, target.innerHeight][event.deltaMode] ?? 1
    scrub(event.deltaY * unit)
    event.preventDefault()
  }

  let touchY: number | undefined
  let touchAt = 0
  // Pixels per millisecond the finger was last moving at, smoothed over the last few moves.
  let touchVelocity = 0
  function onTouchStart(event: TouchEvent) {
    touchY = event.touches.length === 1 ? event.touches[0].clientY : undefined
    touchAt = event.timeStamp
    touchVelocity = 0
  }
  function onTouchMove(event: TouchEvent) {
    if (touchY === undefined || event.touches.length !== 1) return
    const y = event.touches[0].clientY
    const pixels = (touchY - y) * touchGain
    const elapsed = Math.max(event.timeStamp - touchAt, 1)
    touchVelocity = 0.5 * touchVelocity + 0.5 * (pixels / elapsed)
    scrub(pixels)
    touchY = y
    touchAt = event.timeStamp
    event.preventDefault()
  }
  function onTouchEnd(event: TouchEvent) {
    if (touchY !== undefined && event.timeStamp - touchAt < flickStaleMs) {
      scrub(touchVelocity * flickCarrySeconds * 1000)
    }
    touchY = undefined
  }

  const active = { passive: false }
  target.addEventListener('keydown', onKeyDown)
  target.addEventListener('pointermove', onPointerMove)
  target.addEventListener('wheel', onWheel, active)
  target.addEventListener('touchstart', onTouchStart)
  target.addEventListener('touchmove', onTouchMove, active)
  target.addEventListener('touchend', onTouchEnd)
  return () => {
    target.removeEventListener('keydown', onKeyDown)
    target.removeEventListener('pointermove', onPointerMove)
    target.removeEventListener('wheel', onWheel)
    target.removeEventListener('touchstart', onTouchStart)
    target.removeEventListener('touchmove', onTouchMove)
    target.removeEventListener('touchend', onTouchEnd)
  }
}
