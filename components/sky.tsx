'use client'

import { useEffect, useRef, useState } from 'react'
import type { Vec3 } from '@/sky/math'

/**
 * The sky canvas. The engine is a separate chunk, imported only after hydration so the
 * static blank page paints instantly; it reveals itself in-shader once its first frame is
 * ready. Without WebGPU (or if the GPU is lost) a still CSS dusk fades in instead.
 *
 * On iOS Safari the page is held scrolled so the sky runs under the browser's bars, and the
 * page's background follows the sky's edges, which is the colour those bars fade into (see
 * globals.css).
 */
export function Sky() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [fallback, setFallback] = useState(false)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const abort = new AbortController()
    const showFallback = () => {
      clearPageColor()
      setFallback(true)
    }
    const onEdgeColors = bleedTop() ? matchPageColor : undefined
    let stop: (() => void) | undefined

    import('@/sky')
      .then(({ start }) => start(canvas, { signal: abort.signal, onLost: showFallback, onEdgeColors }))
      .then((stopEngine) => {
        if (abort.signal.aborted) stopEngine()
        else stop = stopEngine
      })
      .catch((error: unknown) => {
        if (abort.signal.aborted) return
        console.warn('Skylight: WebGPU sky unavailable, showing a still one instead.', error)
        showFallback()
      })

    return () => {
      abort.abort()
      stop?.()
      clearPageColor()
    }
  }, [])

  useEffect(pinScroll, [])

  return fallback ? <div className="sky-fallback" /> : <canvas ref={canvasRef} className="sky" />
}

/** The top bleed in CSS pixels, set only where the sky runs under the browser's bars. */
function bleedTop() {
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--bleed-top')) || 0
}

/**
 * Safari fades both bars into one colour, the page's background, so it is set between the two
 * edges' colours. On body, which is painted over the root's theme colour.
 */
function matchPageColor(top: Vec3, bottom: Vec3) {
  const channel = (i: number) => Math.round(((top[i] + bottom[i]) / 2) * 255)
  document.body.style.backgroundColor = `rgb(${channel(0)} ${channel(1)} ${channel(2)})`
}

function clearPageColor() {
  document.body.style.removeProperty('background-color')
}

/**
 * Holds the page scrolled by the top bleed so the sky reaches under iOS Safari's status bar (see
 * globals.css). Everywhere else the bleed is unset and this does nothing. Scrolling is re-pinned
 * whenever it moves, as when a tap on the status bar scrolls the page to the top.
 */
function pinScroll() {
  const bleed = bleedTop()
  if (!bleed) return

  const pin = () => {
    if (scrollY !== bleed) scrollTo({ top: bleed, behavior: 'instant' })
  }
  pin()
  addEventListener('scroll', pin, { passive: true })
  addEventListener('resize', pin)
  return () => {
    removeEventListener('scroll', pin)
    removeEventListener('resize', pin)
  }
}
