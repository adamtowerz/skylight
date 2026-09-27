/**
 * Invisible controls. URL parameters set the scene up (`?hour=18.4&speed=0&mood=2`);
 * ←/→ nudge time by a quarter hour, space pauses, and the pointer adds a touch of parallax.
 */

import type { Camera } from './camera'
import type { Clock } from './clock'

const nudgeHours = 0.25

export interface Params {
  hour?: number
  speed?: number
  mood?: number
}

function numberParam(search: URLSearchParams, name: string) {
  const raw = search.get(name)
  const value = raw === null ? NaN : Number(raw)
  return Number.isFinite(value) ? value : undefined
}

export function readParams(query: string): Params {
  const search = new URLSearchParams(query)
  const mood = numberParam(search, 'mood')
  return {
    hour: numberParam(search, 'hour'),
    speed: numberParam(search, 'speed'),
    mood: mood === undefined ? undefined : Math.round(mood),
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

  target.addEventListener('keydown', onKeyDown)
  target.addEventListener('pointermove', onPointerMove)
  return () => {
    target.removeEventListener('keydown', onKeyDown)
    target.removeEventListener('pointermove', onPointerMove)
  }
}
