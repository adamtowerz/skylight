/**
 * The frame loop: requestAnimationFrame with a clamped timestep, paused while the tab is
 * hidden so a background tab costs nothing and returns without a time jump.
 */

/** Longest step the simulation takes, so a hitch never teleports the sky. */
const maxDt = 0.1

/** Calls `frame(dt, time)` every animation frame (seconds). Returns the stop function. */
export function runLoop(frame: (dt: number, time: number) => void): () => void {
  let request = 0
  let last: number | undefined
  let time = 0

  function tick(now: number) {
    const dt = last === undefined ? 0 : Math.min((now - last) / 1000, maxDt)
    last = now
    time += dt
    frame(dt, time)
    request = requestAnimationFrame(tick)
  }

  function onVisibilityChange() {
    cancelAnimationFrame(request)
    last = undefined
    if (!document.hidden) request = requestAnimationFrame(tick)
  }

  document.addEventListener('visibilitychange', onVisibilityChange)
  if (!document.hidden) request = requestAnimationFrame(tick)

  return () => {
    cancelAnimationFrame(request)
    document.removeEventListener('visibilitychange', onVisibilityChange)
  }
}
