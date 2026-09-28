#!/usr/bin/env node
/**
 * Measures the sky's GPU time per frame and per pass, without touching the engine: an init
 * script wraps the WebGPU API before the page runs, asks the device for `timestamp-query`, gives
 * every pass of every `frame` command encoder timestamp writes, and reads them back each frame.
 *
 *   node scripts/frametime.mjs --url 'http://localhost:3417/?hour=18.8&speed=0&mood=1' \
 *     [--size 1440x900] [--dpr 1] [--warmup 4000] [--seconds 5] [--headed]
 *
 * Prints the median and 90th percentile, per pass (labelled as in the engine) and for the whole
 * frame. On Apple GPUs a pass's begin timestamp reads as the frame's start, so each pass is timed
 * from the end of the one before it. Numbers move with the GPU's clock (an idle M1 Pro reads
 * slower than a busy one), so compare before and after in the same session, not across days.
 */

import { parseArgs } from 'node:util'
import { launchChrome, openPage, requireWebGpu } from './browser.mjs'

const { values } = parseArgs({
  options: {
    url: { type: 'string', default: 'http://localhost:3417/?hour=18.8&speed=0' },
    size: { type: 'string', default: '1440x900' },
    dpr: { type: 'string', default: '1' },
    warmup: { type: 'string', default: '4000' },
    seconds: { type: 'string', default: '5' },
    headed: { type: 'boolean', default: false },
  },
})

/** Runs in the page before any of its scripts. Collects `{ labels, ns }` per frame in `__frames`. */
function instrument() {
  const maxPasses = 16
  const frames = (window.__frames = [])
  const passes = new WeakMap()

  const requestDevice = GPUAdapter.prototype.requestDevice
  GPUAdapter.prototype.requestDevice = function (descriptor = {}) {
    if (!this.features.has('timestamp-query')) throw new Error('This adapter has no timestamp-query')
    const requiredFeatures = [...(descriptor.requiredFeatures ?? []), 'timestamp-query']
    return requestDevice.call(this, { ...descriptor, requiredFeatures })
  }

  const createCommandEncoder = GPUDevice.prototype.createCommandEncoder
  GPUDevice.prototype.createCommandEncoder = function (descriptor) {
    const encoder = createCommandEncoder.call(this, descriptor)
    if (descriptor?.label === 'frame') {
      const querySet = this.createQuerySet({ type: 'timestamp', count: maxPasses * 2 })
      passes.set(encoder, { device: this, querySet, labels: [] })
    }
    return encoder
  }

  const timed = (begin) =>
    function (descriptor) {
      const state = passes.get(this)
      if (!state || state.labels.length === maxPasses) return begin.call(this, descriptor)
      const index = state.labels.push(descriptor.label ?? '?') - 1
      const timestampWrites = { querySet: state.querySet, beginningOfPassWriteIndex: index * 2, endOfPassWriteIndex: index * 2 + 1 }
      return begin.call(this, { ...descriptor, timestampWrites })
    }
  GPUCommandEncoder.prototype.beginComputePass = timed(GPUCommandEncoder.prototype.beginComputePass)
  GPUCommandEncoder.prototype.beginRenderPass = timed(GPUCommandEncoder.prototype.beginRenderPass)

  const finish = GPUCommandEncoder.prototype.finish
  GPUCommandEncoder.prototype.finish = function (descriptor) {
    const state = passes.get(this)
    if (state?.labels.length) {
      const size = state.labels.length * 2 * 8
      const resolve = state.device.createBuffer({ size, usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC })
      const readback = state.device.createBuffer({ size, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST })
      this.resolveQuerySet(state.querySet, 0, state.labels.length * 2, resolve, 0)
      this.copyBufferToBuffer(resolve, 0, readback, 0, size)
      state.device.queue.onSubmittedWorkDone().then(async () => {
        await readback.mapAsync(GPUMapMode.READ)
        frames.push({ labels: state.labels, ns: Array.from(new BigInt64Array(readback.getMappedRange()), Number) })
        for (const buffer of [readback, resolve]) buffer.destroy()
        state.querySet.destroy()
      })
    }
    return finish.call(this, descriptor)
  }
}

const browser = await launchChrome({ headed: values.headed, args: ['--enable-webgpu-developer-features'] })
try {
  const page = await openPage(browser, values)
  await page.addInitScript(instrument)
  await page.goto(values.url, { waitUntil: 'load' })
  console.log(`WebGPU adapter: ${await requireWebGpu(page)}`)
  await page.waitForTimeout(Number(values.warmup))
  const skip = await page.evaluate(() => window.__frames.length)
  await page.waitForTimeout(Number(values.seconds) * 1000)
  const frames = (await page.evaluate(() => window.__frames)).slice(skip)
  if (!frames.length) throw new Error('No frames were timed: did the engine start, and is its encoder still labelled "frame"?')

  const percentile = (samples, p) => samples.toSorted((a, b) => a - b)[Math.min(samples.length - 1, Math.floor(p * samples.length))]
  const rows = new Map()
  const add = (label, ms) => rows.set(label, [...(rows.get(label) ?? []), ms])
  for (const { labels, ns } of frames) {
    labels.forEach((label, i) => add(label, (ns[i * 2 + 1] - (i ? ns[i * 2 - 1] : ns[0])) / 1e6))
    add('frame', (ns[ns.length - 1] - ns[0]) / 1e6)
  }
  console.log(`${frames.length} frames at ${values.size} × ${values.dpr} DPR (${values.url})`)
  console.log('pass              median ms   p90 ms')
  for (const [label, samples] of rows) {
    console.log(`${label.padEnd(18)}${percentile(samples, 0.5).toFixed(2).padStart(9)}${percentile(samples, 0.9).toFixed(2).padStart(9)}`)
  }
} finally {
  await browser.close()
}
