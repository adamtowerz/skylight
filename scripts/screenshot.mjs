#!/usr/bin/env node
/**
 * Screenshots the sky in a real WebGPU browser (installed Google Chrome, via Playwright).
 *
 *   node scripts/screenshot.mjs --url 'http://localhost:3000/?hour=18.2&speed=0' \
 *     --out .context/sunset.png --wait 5000 [--size 1440x900] [--dpr 2] [--theme light] [--headed]
 *
 * Several `--wait` values (e.g. `--wait 0,1500,5000`) capture a sequence from one page load,
 * suffixing the output name with the elapsed milliseconds. `--dpr 2` renders at a retina device
 * pixel ratio (the PNG is then twice the size). Console errors are echoed, and the run fails if
 * the page reports no WebGPU adapter.
 */

import { parseArgs } from 'node:util'
import { chromium } from 'playwright'

const { values } = parseArgs({
  options: {
    url: { type: 'string', default: 'http://localhost:3000/' },
    out: { type: 'string', default: '.context/screenshot.png' },
    wait: { type: 'string', default: '5000' },
    size: { type: 'string', default: '1440x900' },
    dpr: { type: 'string', default: '1' },
    theme: { type: 'string', default: 'dark' },
    headed: { type: 'boolean', default: false },
  },
})

const [width, height] = values.size.split('x').map(Number)
const waits = values.wait.split(',').map(Number).sort((a, b) => a - b)

const browser = await chromium.launch({
  channel: 'chrome',
  headless: !values.headed,
  args: ['--enable-unsafe-webgpu', '--enable-gpu', '--ignore-gpu-blocklist', '--use-angle=metal'],
})

try {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: Number(values.dpr), colorScheme: values.theme })
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning') console.log(`[${message.type()}] ${message.text()}`)
  })
  page.on('pageerror', (error) => console.log(`[pageerror] ${error.message}`))

  await page.goto(values.url, { waitUntil: 'load' })
  const adapter = await page.evaluate(async () => {
    const found = await navigator.gpu?.requestAdapter()
    return found ? `${found.info.vendor} ${found.info.architecture}`.trim() || 'available' : null
  })
  if (!adapter) throw new Error('No WebGPU adapter in this browser; try --headed')
  console.log(`WebGPU adapter: ${adapter}`)

  const start = Date.now()
  for (const wait of waits) {
    await page.waitForTimeout(Math.max(0, wait - (Date.now() - start)))
    const path = waits.length > 1 ? values.out.replace(/(\.\w+)?$/, `-${wait}ms$1`) : values.out
    await page.screenshot({ path })
    console.log(`Saved ${path}`)
  }
} finally {
  await browser.close()
}
