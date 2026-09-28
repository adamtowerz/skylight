/**
 * The installed Google Chrome with WebGPU on, shared by the render-review scripts. Headless
 * Chrome on macOS gets a real Metal adapter with these flags; `--headed` is the escape hatch
 * when it does not.
 */

import { chromium } from 'playwright'

const webGpuArgs = ['--enable-unsafe-webgpu', '--enable-gpu', '--ignore-gpu-blocklist', '--use-angle=metal']

export function launchChrome({ headed = false, args = [] } = {}) {
  return chromium.launch({ channel: 'chrome', headless: !headed, args: [...webGpuArgs, ...args] })
}

/** `1440x900` → `[1440, 900]`. */
export function parseSize(size) {
  const [width, height] = size.split('x').map(Number)
  if (!(width > 0 && height > 0)) throw new Error(`Bad size "${size}", expected WIDTHxHEIGHT`)
  return [width, height]
}

/**
 * A page at the given size, pixel ratio and colour scheme that echoes console errors and
 * warnings. `still` asks for reduced motion, which stills the camera's breathing.
 */
export async function openPage(browser, { size = '1440x900', dpr = 1, theme = 'dark', still = false, tag = '' } = {}) {
  const [width, height] = parseSize(size)
  const page = await browser.newPage({
    viewport: { width, height },
    deviceScaleFactor: Number(dpr),
    colorScheme: theme,
    reducedMotion: still ? 'reduce' : 'no-preference',
  })
  const prefix = tag ? `${tag} ` : ''
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning') console.log(`${prefix}[${message.type()}] ${message.text()}`)
  })
  page.on('pageerror', (error) => console.log(`${prefix}[pageerror] ${error.message}`))
  return page
}

/** Throws unless the page can get a WebGPU adapter: a sky that silently fell back is no evidence. */
export async function requireWebGpu(page) {
  const adapter = await page.evaluate(async () => {
    const found = await navigator.gpu?.requestAdapter()
    return found ? `${found.info.vendor} ${found.info.architecture}`.trim() || 'available' : null
  })
  if (!adapter) throw new Error('No WebGPU adapter in this browser; try --headed')
  return adapter
}

/** Comma-separated list option → array (empty or missing → `fallback`). */
export const list = (value, fallback = []) => (value ? value.split(',').map((item) => item.trim()).filter(Boolean) : fallback)
