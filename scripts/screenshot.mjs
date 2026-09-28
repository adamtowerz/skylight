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
 * the page reports no WebGPU adapter. For a matrix of hours and moods, see `shots.mjs`.
 */

import { parseArgs } from 'node:util'
import { launchChrome, list, openPage, requireWebGpu } from './browser.mjs'

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

const waits = list(values.wait).map(Number).sort((a, b) => a - b)
const browser = await launchChrome({ headed: values.headed })

try {
  const page = await openPage(browser, values)
  await page.goto(values.url, { waitUntil: 'load' })
  console.log(`WebGPU adapter: ${await requireWebGpu(page)}`)

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
