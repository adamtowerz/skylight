'use client'

import { useEffect, useRef, useState } from 'react'

/**
 * The sky canvas. The engine is a separate chunk, imported only after hydration so the
 * static blank page paints instantly; it reveals itself in-shader once its first frame is
 * ready. Without WebGPU (or if the GPU is lost) a still CSS dusk fades in instead.
 */
export function Sky() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [fallback, setFallback] = useState(false)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const abort = new AbortController()
    const showFallback = () => setFallback(true)
    let stop: (() => void) | undefined

    import('@/sky')
      .then(({ start }) => start(canvas, { signal: abort.signal, onLost: showFallback }))
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
    }
  }, [])

  return fallback ? <div className="sky-fallback" /> : <canvas ref={canvasRef} className="sky" />
}
