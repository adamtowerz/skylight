#!/usr/bin/env node
/**
 * Renders a matrix of frozen skies (hours × moods × pixel ratios × themes) in one browser, one
 * PNG each, named predictably so two runs (a baseline and a change) pair up by filename in
 * `sheet.mjs --before … --after …`.
 *
 *   node scripts/shots.mjs --base http://localhost:3417 --hours 7,13,18.3,18.8,19.1,23 \
 *     [--moods 0,1,2] [--dpr 1,2] [--theme dark,light] [--size 1440x900] [--wait 6000] \
 *     [--params 'speed=1'] [--motion] [--headed] --out .context/shots/<tag>
 *
 * Names are `h<hour>[-m<mood>][-dpr<ratio>][-<theme>][-<wait>ms].png`: the hour always, the
 * others only when that option was given (the wait only when there are several). Every URL has
 * `speed=0` so the sky holds still; `--params` is appended after it and can override it. Pages
 * also ask for reduced motion, which stills the camera's breathing, so the same shot from two
 * builds lines up to the pixel (only the grain still differs); `--motion` keeps the breath.
 *
 * Shots run one page at a time. Pages in parallel share the one GPU: a starved page averages
 * fewer frames into its clouds, adapts its exposure more slowly, and with three at once a page
 * can take seconds to show its first frame, so it is caught mid-reveal.
 */

import { mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { parseArgs } from 'node:util'
import { launchChrome, list, openPage, requireWebGpu } from './browser.mjs'

const { values } = parseArgs({
  options: {
    base: { type: 'string', default: 'http://localhost:3417' },
    hours: { type: 'string', default: '7,13,18.3,18.8,19.1,23' },
    moods: { type: 'string' },
    dpr: { type: 'string' },
    theme: { type: 'string' },
    size: { type: 'string', default: '1440x900' },
    wait: { type: 'string', default: '6000' },
    params: { type: 'string', default: '' },
    motion: { type: 'boolean', default: false },
    headed: { type: 'boolean', default: false },
    out: { type: 'string' },
  },
})
if (!values.out) throw new Error('--out <directory> is required, e.g. --out .context/shots/before')

const waits = list(values.wait).map(Number).sort((a, b) => a - b)
const optional = (value) => list(value, [undefined])

const shots = []
for (const hour of list(values.hours))
  for (const mood of optional(values.moods))
    for (const dpr of optional(values.dpr))
      for (const theme of optional(values.theme)) {
        const name = [`h${hour}`, mood && `m${mood}`, dpr && `dpr${dpr}`, theme].filter(Boolean).join('-')
        const query = new URLSearchParams({ hour, speed: '0', ...(mood && { mood }) })
        for (const [key, value] of new URLSearchParams(values.params)) query.set(key, value)
        shots.push({ name, url: `${values.base.replace(/\/$/, '')}/?${query}`, dpr: dpr ?? 1, theme: theme ?? 'dark' })
      }

mkdirSync(values.out, { recursive: true })
const browser = await launchChrome({ headed: values.headed })

async function take({ name, url, dpr, theme }) {
  const page = await openPage(browser, { size: values.size, dpr, theme, still: !values.motion, tag: name })
  try {
    await page.goto(url, { waitUntil: 'load' })
    await requireWebGpu(page)
    const start = Date.now()
    for (const wait of waits) {
      await page.waitForTimeout(Math.max(0, wait - (Date.now() - start)))
      const path = join(values.out, `${name}${waits.length > 1 ? `-${wait}ms` : ''}.png`)
      await page.screenshot({ path })
      console.log(`Saved ${path}  ← ${url}`)
    }
  } finally {
    await page.close()
  }
}

try {
  for (const shot of shots) await take(shot)
} finally {
  await browser.close()
}
