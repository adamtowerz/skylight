/**
 * Reads back the average colour of the output's top and bottom rows a few times a second, for
 * hosts that match the page around the canvas to the sky (iOS Safari fades its bars into the
 * page's background colour). Two rows of the swap chain texture are copied into a mappable
 * buffer; while a read is in flight no new copy is made, so it never stalls the frame.
 */

import type { Vec3 } from './math'

/** Frames between reads: the sky drifts slowly, and the page colour transitions anyway. */
const interval = 15

export type EdgeColors = (top: Vec3, bottom: Vec3) => void

export interface EdgeSampler {
  /** Encodes this frame's copy, if one is due; call after the output is drawn. */
  encode(encoder: GPUCommandEncoder, output: GPUTexture): void
  /** Starts reading the copy once the frame's commands are submitted. */
  submitted(): void
  destroy(): void
}

export function createEdgeSampler(device: GPUDevice, format: GPUTextureFormat, onColors: EdgeColors): EdgeSampler {
  const bgra = format.startsWith('bgra')
  let buffer: GPUBuffer | undefined
  let rowBytes = 0
  let width = 0
  let frame = 0
  let busy = false
  let copied = false

  function average(bytes: Uint8Array, offset: number): Vec3 {
    let r = 0
    let g = 0
    let b = 0
    for (let i = offset; i < offset + width * 4; i += 4) {
      r += bytes[i]
      g += bytes[i + 1]
      b += bytes[i + 2]
    }
    const scale = 1 / (255 * width)
    return bgra ? [b * scale, g * scale, r * scale] : [r * scale, g * scale, b * scale]
  }

  return {
    encode(encoder, output) {
      if (busy || frame++ % interval) return
      if (output.width !== width || !buffer) {
        buffer?.destroy()
        width = output.width
        rowBytes = Math.ceil((width * 4) / 256) * 256
        buffer = device.createBuffer({
          label: 'edges',
          size: rowBytes * 2,
          usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
        })
      }
      for (const [row, offset] of [
        [0, 0],
        [output.height - 1, rowBytes],
      ]) {
        encoder.copyTextureToBuffer(
          { texture: output, origin: [0, row] },
          { buffer, offset, bytesPerRow: rowBytes },
          [width, 1],
        )
      }
      copied = true
    },

    submitted() {
      if (!copied || !buffer) return
      copied = false
      busy = true
      const reading = buffer
      reading
        .mapAsync(GPUMapMode.READ)
        .then(() => {
          const bytes = new Uint8Array(reading.getMappedRange())
          onColors(average(bytes, 0), average(bytes, rowBytes))
          reading.unmap()
        })
        // Destroyed mid-read (resize or stop); the next copy starts afresh.
        .catch(() => {})
        .finally(() => (busy = false))
    },

    destroy() {
      buffer?.destroy()
    },
  }
}
