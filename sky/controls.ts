/**
 * Invisible controls. URL parameters set the scene up (`?hour=18.4&speed=0&mood=2`, or
 * `?seed=3` for one of the opening moments), and any kind of weather can be held at a value over
 * the timeline (`?fog=0.8&haze=0.5`, each 0 → 1); scrolling (or dragging on touch screens) winds
 * time back and forth, ←/→ nudge it by a quarter hour, space pauses, and the pointer adds a
 * touch of parallax.
 */

import type { Camera } from './camera'
import type { Clock } from './clock'
import { weatherKinds, type Weather } from './weather'

const nudgeHours = 0.25
/** Natural seconds of clock per pixel scrolled: a wheel notch is a few minutes at dusk, a swipe an hour. */
const scrubSecondsPerPixel = 0.02
/** Pixels per line, for wheels that scroll by lines. */
const pixelsPerLine = 16

export interface Params {
  hour?: number
  speed?: number
  mood?: number
  seed?: number
  /** Weather held at these values whatever the timeline says. */
  weather: Partial<Weather>
}

function numberParam(search: URLSearchParams, name: string) {
  const raw = search.get(name)
  const value = raw === null ? NaN : Number(raw)
  return Number.isFinite(value) ? value : undefined
}

/** Every kind of weather given a value, e.g. `?fog=0.8`. */
function heldWeather(search: URLSearchParams) {
  const held: Partial<Weather> = {}
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
  function onTouchStart(event: TouchEvent) {
    touchY = event.touches.length === 1 ? event.touches[0].clientY : undefined
  }
  function onTouchMove(event: TouchEvent) {
    if (touchY === undefined || event.touches.length !== 1) return
    const y = event.touches[0].clientY
    scrub(touchY - y)
    touchY = y
    event.preventDefault()
  }

  const active = { passive: false }
  target.addEventListener('keydown', onKeyDown)
  target.addEventListener('pointermove', onPointerMove)
  target.addEventListener('wheel', onWheel, active)
  target.addEventListener('touchstart', onTouchStart)
  target.addEventListener('touchmove', onTouchMove, active)
  return () => {
    target.removeEventListener('keydown', onKeyDown)
    target.removeEventListener('pointermove', onPointerMove)
    target.removeEventListener('wheel', onWheel)
    target.removeEventListener('touchstart', onTouchStart)
    target.removeEventListener('touchmove', onTouchMove)
  }
}
