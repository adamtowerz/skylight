/**
 * WebGPU acquisition and canvas sizing. The canvas backing store tracks its exact device-pixel
 * size (so post-processing grain and dither land on real pixels), capped at 2× DPR.
 */

const maxPixelRatio = 2

export interface Gpu {
  device: GPUDevice
  context: GPUCanvasContext
  format: GPUTextureFormat
}

/** Rejects when WebGPU is unavailable, or with `signal.reason` if aborted mid-way. */
export async function acquireGpu(canvas: HTMLCanvasElement, signal?: AbortSignal): Promise<Gpu> {
  if (!navigator.gpu) throw new Error('WebGPU is not supported')
  const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' })
  if (!adapter) throw new Error('No WebGPU adapter')
  const device = await adapter.requestDevice({ label: 'skylight' })

  const context = canvas.getContext('webgpu')
  if (!context || signal?.aborted) {
    device.destroy()
    signal?.throwIfAborted()
    throw new Error('No WebGPU canvas context')
  }
  const format = navigator.gpu.getPreferredCanvasFormat()
  context.configure({ device, format, alphaMode: 'opaque' })
  return { device, context, format }
}

/**
 * Keeps the canvas backing store matched to its on-screen size in device pixels and reports
 * every change. Returns the disconnect function.
 */
export function observeCanvasSize(
  canvas: HTMLCanvasElement,
  maxDimension: number,
  onResize: (width: number, height: number) => void,
): () => void {
  const observer = new ResizeObserver(([entry]) => {
    const ratio = devicePixelRatio
    const cap = Math.min(1, maxPixelRatio / ratio)
    const box = entry.devicePixelContentBoxSize?.[0]
    const width = box ? box.inlineSize : entry.contentBoxSize[0].inlineSize * ratio
    const height = box ? box.blockSize : entry.contentBoxSize[0].blockSize * ratio
    canvas.width = Math.max(1, Math.min(maxDimension, Math.round(width * cap)))
    canvas.height = Math.max(1, Math.min(maxDimension, Math.round(height * cap)))
    onResize(canvas.width, canvas.height)
  })
  try {
    observer.observe(canvas, { box: 'device-pixel-content-box' })
  } catch {
    // Safari cannot observe device pixels; the CSS box × DPR is close enough.
    observer.observe(canvas)
  }
  return () => observer.disconnect()
}
