/**
 * Skylight: a framework-free WebGPU sky. Give it a canvas; get back a function that stops it
 * and releases everything. Each frame the CPU only advances time, places the sun, moon and
 * camera, fills one uniform buffer and encodes the frame graph.
 */

import { createCamera } from './camera'
import { celestial } from './celestial'
import { createClock } from './clock'
import { bindControls, readParams } from './controls'
import type { EdgeColors } from './edges'
import { acquireGpu, observeCanvasSize, type Gpu } from './gpu'
import { trackHistory } from './history'
import { runLoop } from './loop'
import { smoothstep, type Vec2, type Vec3 } from './math'
import { moodCycle } from './moods'
import { createRenderer, type Renderer } from './renderer'
import { openingMoment } from './seeds'
import { fillUniforms, Uniforms } from './uniforms'
import { weatherAt } from './weather'

/** How long the eyes take to open once the first frame is ready. */
const revealSeconds = 3.5

export interface StartOptions {
  /** Aborting before `start` resolves releases everything and rejects with the abort reason. */
  signal?: AbortSignal
  /** Called if the GPU device is lost; the engine has already stopped itself. */
  onLost?: () => void
  /** Called a few times a second with the average colour of the top and bottom rows. */
  onEdgeColors?: EdgeColors
}

/**
 * The page's background, display-encoded: the blank first paint the sky is revealed from. Read
 * from the root, since body's may be following the sky's edges.
 */
function pageBackground(element: Element): Vec3 {
  const [r = 0, g = 0, b = 0] = getComputedStyle(element).backgroundColor.match(/[\d.]+/g)?.map(Number) ?? []
  return [r / 255, g / 255, b / 255]
}

/** Rejects when WebGPU is unavailable, so the caller can show a fallback. */
export async function start(
  canvas: HTMLCanvasElement,
  { signal, onLost, onEdgeColors }: StartOptions = {},
): Promise<() => void> {
  const gpu = await acquireGpu(canvas, signal)
  try {
    const renderer = await createRenderer(gpu, onEdgeColors)
    signal?.throwIfAborted()
    return run(canvas, gpu, renderer, onLost)
  } catch (error) {
    gpu.device.destroy()
    throw error
  }
}

function run(canvas: HTMLCanvasElement, { device }: Gpu, renderer: Renderer, onLost?: () => void) {
  const params = readParams(location.search)
  const opening = openingMoment(params)
  const clock = createClock({ hours: opening.hours, speed: params.speed })
  const moodAt = moodCycle(opening.hours, opening.mood)
  const camera = createCamera(matchMedia('(prefers-reduced-motion: reduce)').matches)
  const history = trackHistory()
  const uniforms = Uniforms.create()

  let resolution: Vec2 | undefined
  let outputResolution: Vec2 = [1, 1]
  let frame = 0
  let revealStart: number | undefined
  let blankColor = pageBackground(document.documentElement)

  const theme = matchMedia('(prefers-color-scheme: light)')
  const onThemeChange = () => (blankColor = pageBackground(document.documentElement))
  theme.addEventListener('change', onThemeChange)

  const unobserve = observeCanvasSize(canvas, device.limits.maxTextureDimension2D, (width, height) => {
    outputResolution = [width, height]
    resolution = renderer.resize(width, height)
    history.reset()
  })
  const unbind = bindControls(window, clock, camera)

  const stopLoop = runLoop((dt, time) => {
    if (!resolution) return
    clock.advance(dt)
    const sky = celestial(clock.hour)
    camera.update(dt, time)
    revealStart ??= time
    const view = camera.basis(outputResolution[0] / outputResolution[1])

    fillUniforms(uniforms, {
      resolution,
      outputResolution,
      time,
      dt,
      frame: frame++,
      reveal: smoothstep(0, revealSeconds, time - revealStart),
      blankColor,
      hours: clock.hours,
      weather: weatherAt(clock.hours, params.weather),
      camera: view,
      history: history.next(view, clock.hours),
      sky,
      mood: moodAt(clock.hours),
    })
    renderer.render(uniforms.data)
  })

  let stopped = false
  function stop() {
    if (stopped) return
    stopped = true
    stopLoop()
    unbind()
    unobserve()
    theme.removeEventListener('change', onThemeChange)
    renderer.destroy()
    device.destroy()
  }

  // Loss is expected (driver resets, sleep); stop quietly and let the host fall back.
  device.lost.then(() => {
    if (stopped) return
    stop()
    onLost?.()
  })

  return stop
}
