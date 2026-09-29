/**
 * Temporal stability for `shots.mjs --burst`: copies a run of consecutive frames straight out of
 * the WebGPU canvas (screenshots are too slow to catch neighbouring frames) and measures how much
 * each pixel flickers from one frame to the next. Stills hide flicker; this is how shimmering
 * cloud edges, combing and jumping light shafts show up.
 *
 * Film grain refreshes at 12 fps and would drown everything else, so the frame pairs across a
 * grain change are left out: flicker is the RMS of the remaining frame-to-frame luma differences
 * over √2 (the standard deviation of a pixel that is steady but for noise), in 8-bit levels.
 */

/** Before the page loads: after every animation frame that drew the sky, copy it if asked to. */
export function installFrameCapture(page) {
  return page.addInitScript(() => {
    const capture = { wanted: 0, frames: [] }
    window.__skylightCapture = capture
    let drew = false
    const getCurrentTexture = GPUCanvasContext.prototype.getCurrentTexture
    GPUCanvasContext.prototype.getCurrentTexture = function () {
      drew = true
      return getCurrentTexture.call(this)
    }
    const request = window.requestAnimationFrame.bind(window)
    window.requestAnimationFrame = (callback) =>
      request((now) => {
        drew = false
        callback(now)
        if (!drew || capture.wanted === 0) return
        const source = document.querySelector('canvas')
        const copy = new OffscreenCanvas(source.width, source.height)
        copy.getContext('2d').drawImage(source, 0, 0)
        capture.frames.push(copy)
        capture.wanted--
      })
  })
}

/**
 * Captures `count` consecutive frames; returns the flicker's mean and 99th percentile, and a PNG
 * (data URL) of it per pixel, `gain` levels of grey per level of flicker.
 */
export async function measureFlicker(page, { count = 16, gain = 40 } = {}) {
  await page.evaluate((n) => Object.assign(window.__skylightCapture, { wanted: n, frames: [] }), count)
  await page.waitForFunction(() => window.__skylightCapture.wanted === 0, null, { timeout: 30000 })
  return page.evaluate(async (gain) => {
    const lumas = window.__skylightCapture.frames.map((frame) => {
      const { data } = frame.getContext('2d').getImageData(0, 0, frame.width, frame.height)
      const luma = new Float32Array(data.length / 4)
      for (let i = 0; i < luma.length; i++) luma[i] = 0.2126 * data[4 * i] + 0.7152 * data[4 * i + 1] + 0.0722 * data[4 * i + 2]
      return luma
    })
    const { width, height } = window.__skylightCapture.frames[0]
    const diffs = lumas.slice(1).map((luma, f) => luma.map((value, i) => value - lumas[f][i]))
    const energy = diffs.map((diff) => diff.reduce((sum, value) => sum + Math.abs(value), 0))
    const median = [...energy].sort((a, b) => a - b)[Math.floor(energy.length / 2)]
    const steady = diffs.filter((_, f) => energy[f] <= 1.5 * median)
    const flicker = new Float32Array(width * height)
    for (const diff of steady) for (let i = 0; i < flicker.length; i++) flicker[i] += diff[i] * diff[i]
    for (let i = 0; i < flicker.length; i++) flicker[i] = Math.sqrt(flicker[i] / steady.length / 2)

    const map = new OffscreenCanvas(width, height)
    const context = map.getContext('2d')
    const image = context.createImageData(width, height)
    flicker.forEach((value, i) => {
      image.data.fill(Math.min(255, value * gain), 4 * i, 4 * i + 3)
      image.data[4 * i + 3] = 255
    })
    context.putImageData(image, 0, 0)
    const blob = await map.convertToBlob({ type: 'image/png' })
    const png = await new Promise((resolve) => {
      const reader = new FileReader()
      reader.onload = () => resolve(reader.result)
      reader.readAsDataURL(blob)
    })
    const sorted = [...flicker].sort((a, b) => a - b)
    const mean = flicker.reduce((sum, value) => sum + value, 0) / flicker.length
    return { mean, p99: sorted[Math.floor(0.99 * sorted.length)], pairs: steady.length, png }
  }, gain)
}
