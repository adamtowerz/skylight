#!/usr/bin/env node
/**
 * Composes labelled contact sheets and before/after grids from PNGs, with Playwright as the
 * image library: the images are drawn into canvases on a generated page (scaled, cropped,
 * differenced) and the page is screenshotted. No Python, no image dependencies.
 *
 *   # A grid of labelled images (a bare path is labelled with its file name)
 *   node scripts/sheet.mjs 'noon=.context/shots/a/h13.png' .context/shots/a/h18.8.png \
 *     --cols 2 --out .context/sheets/grid.jpg
 *
 *   # Before | after, one row per file name found in both directories, plus an amplified diff
 *   node scripts/sheet.mjs --before .context/shots/before --after .context/shots/after \
 *     [--match 'h18|h19'] [--diff 8] --out .context/sheets/compare.jpg
 *
 *   # 1:1 detail: crop x,y,w,h in source pixels, optionally magnified (nearest neighbour)
 *   … --crop 600,300,400,300 [--scale 2]
 *
 * Without `--scale`, whole images are fitted to `--width` (720) and crops shown at 1:1. With
 * `--diff G` each pair gets a third column, |after − before| × G, and its statistics are printed.
 * Two runs of one build differ only by film grain: an even speckle, mean ≈ 0.1 (same grain frame)
 * or ≈ 3–4 (another one), max ≲ 30 of 255. A real change shows up as structure above that.
 *
 * `--out` ending in `.jpg` writes a JPEG (quality 92): a sheet of many full frames is a PNG of
 * several MB, which image viewers (Claude's included) may downsample into false banding.
 */

import { readdirSync, readFileSync } from 'node:fs'
import { basename, join, resolve } from 'node:path'
import { parseArgs } from 'node:util'
import { chromium } from 'playwright'

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    before: { type: 'string' },
    after: { type: 'string' },
    match: { type: 'string' },
    diff: { type: 'string' },
    cols: { type: 'string' },
    crop: { type: 'string' },
    scale: { type: 'string' },
    width: { type: 'string', default: '720' },
    title: { type: 'string' },
    out: { type: 'string' },
  },
})
if (!values.out) throw new Error('--out <file.png> is required')

const stem = (path) => basename(path).replace(/\.png$/i, '')
const pngs = (dir) => readdirSync(dir).filter((name) => /\.png$/i.test(name)).sort((a, b) => a.localeCompare(b, 'en', { numeric: true }))

/** Rows of cells; a cell is an image `{ label, path }` or a diff `{ label, diff: [before, after] }`. */
let rows
if (values.before || values.after) {
  if (!values.before || !values.after) throw new Error('--before and --after go together')
  const [beforeTag, afterTag] = [values.before, values.after].map((dir) => basename(resolve(dir)))
  const afterNames = new Set(pngs(values.after))
  const pattern = values.match ? new RegExp(values.match) : undefined
  const names = pngs(values.before).filter((name) => afterNames.has(name) && (!pattern || pattern.test(name)))
  if (!names.length) throw new Error(`No file names in common between ${values.before} and ${values.after}`)
  rows = names.map((name) => {
    const before = { label: `${stem(name)} · ${beforeTag}`, path: join(values.before, name) }
    const after = { label: `${stem(name)} · ${afterTag}`, path: join(values.after, name) }
    const diff = values.diff && { label: `${stem(name)} · diff ×${values.diff}`, diff: [0, 1] }
    return [before, after, diff].filter(Boolean)
  })
} else {
  if (!positionals.length) throw new Error('Give images as label=path (or path), or --before/--after directories')
  const cells = positionals.map((arg) => {
    const [label, path] = arg.includes('=') ? [arg.slice(0, arg.indexOf('=')), arg.slice(arg.indexOf('=') + 1)] : [stem(arg), arg]
    return { label, path }
  })
  const cols = Number(values.cols ?? Math.min(cells.length, 3))
  rows = []
  for (let i = 0; i < cells.length; i += cols) rows.push(cells.slice(i, i + cols))
}

// Every image is served from one fake origin, so the canvases stay untainted and readable.
const origin = 'http://sheet.local'
const files = rows.flat().filter((cell) => cell.path).map((cell) => cell.path)
const config = {
  title: values.title,
  crop: values.crop?.split(',').map(Number),
  scale: values.scale ? Number(values.scale) : undefined,
  width: Number(values.width),
  diffGain: Number(values.diff ?? 1),
  rows: rows.map((row) =>
    row.map((cell) => (cell.path ? { label: cell.label, src: `${origin}/${files.indexOf(cell.path)}.png` } : cell)),
  ),
}

/** Runs in the page: draws every cell, returns diff statistics. */
async function compose({ title, crop, scale, width, diffGain, rows }) {
  const load = async ({ src }) => {
    if (!src) return undefined
    const image = new Image()
    image.src = src
    await image.decode()
    return image
  }
  const images = await Promise.all(rows.map((row) => Promise.all(row.map(load))))
  const region = (image) => (crop ? crop : [0, 0, image.naturalWidth, image.naturalHeight])
  const scaleFor = (w) => scale ?? (crop ? 1 : width / w)
  const pixels = (image) => {
    const [x, y, w, h] = region(image)
    const canvas = new OffscreenCanvas(w, h)
    const context = canvas.getContext('2d')
    context.drawImage(image, x, y, w, h, 0, 0, w, h)
    return context.getImageData(0, 0, w, h)
  }
  const draw = (source, [x, y, w, h]) => {
    const k = scaleFor(w)
    const canvas = document.createElement('canvas')
    canvas.width = Math.round(w * k)
    canvas.height = Math.round(h * k)
    const context = canvas.getContext('2d')
    // Magnified crops stay crisp so single pixels can be judged; reductions are filtered.
    context.imageSmoothingEnabled = k < 1
    context.imageSmoothingQuality = 'high'
    context.drawImage(source, x, y, w, h, 0, 0, canvas.width, canvas.height)
    return canvas
  }

  const stats = []
  const sheet = document.querySelector('main')
  if (title) document.querySelector('h1').textContent = title
  rows.forEach((row, r) => {
    const line = document.createElement('div')
    line.className = 'row'
    row.forEach((cell, c) => {
      const figure = document.createElement('figure')
      const caption = document.createElement('figcaption')
      caption.textContent = cell.label
      const image = images[r][c]
      if (image) {
        figure.append(draw(image, region(image)))
        if (crop) caption.textContent += ` · ${crop[2]}×${crop[3]} at ${crop[0]},${crop[1]}`
      } else {
        const [a, b] = cell.diff.map((i) => pixels(images[r][i]))
        if (a.width !== b.width || a.height !== b.height) {
          caption.textContent += ' · sizes differ'
        } else {
          const out = new ImageData(a.width, a.height)
          let sum = 0
          let max = 0
          let changed = 0
          for (let p = 0; p < a.data.length; p += 4) {
            let pixelMax = 0
            for (let k = 0; k < 3; k++) {
              const d = Math.abs(a.data[p + k] - b.data[p + k])
              sum += d
              pixelMax = Math.max(pixelMax, d)
              out.data[p + k] = Math.min(255, d * diffGain)
            }
            out.data[p + 3] = 255
            max = Math.max(max, pixelMax)
            if (pixelMax > 8) changed++
          }
          const count = a.width * a.height
          const stat = { label: cell.label, mean: sum / (count * 3), max, changed: changed / count }
          stats.push(stat)
          caption.textContent += ` · mean ${stat.mean.toFixed(2)} · max ${max} · ${(stat.changed * 100).toFixed(1)}% px > 8`
          const canvas = new OffscreenCanvas(a.width, a.height)
          canvas.getContext('2d').putImageData(out, 0, 0)
          figure.append(draw(canvas, [0, 0, a.width, a.height]))
        }
      }
      figure.append(caption)
      line.append(figure)
    })
    sheet.append(line)
  })
  return stats
}

const page = `<!doctype html><meta charset="utf-8"><style>
  body { margin: 0; padding: 16px; background: #111; color: #ddd; font: 13px/1.3 ui-monospace, Menlo, monospace; width: max-content; }
  h1 { margin: 0 0 12px; font-size: 15px; font-weight: 600; }
  h1:empty { display: none; }
  .row { display: flex; gap: 8px; margin-bottom: 8px; align-items: flex-start; }
  figure { margin: 0; }
  canvas { display: block; }
  figcaption { padding: 4px 0 0; white-space: nowrap; }
</style><h1></h1><main></main>`

const browser = await chromium.launch({ channel: 'chrome' })
try {
  // A tiny viewport, so the full-page screenshot is exactly the sheet's own size.
  const tab = await browser.newPage({ viewport: { width: 16, height: 16 }, deviceScaleFactor: 1 })
  await tab.route(`${origin}/**`, (route) => {
    const path = new URL(route.request().url()).pathname.slice(1)
    if (!path) return route.fulfill({ contentType: 'text/html', body: page })
    return route.fulfill({ contentType: 'image/png', body: readFileSync(files[Number.parseInt(path)]) })
  })
  await tab.goto(`${origin}/`)
  const stats = await tab.evaluate(compose, config)
  for (const { label, mean, max, changed } of stats) {
    console.log(`${label}: mean ${mean.toFixed(2)}, max ${max}, ${(changed * 100).toFixed(1)}% of pixels differ by > 8/255`)
  }
  const jpeg = /\.jpe?g$/i.test(values.out)
  await tab.screenshot({ path: values.out, fullPage: true, ...(jpeg && { type: 'jpeg', quality: 92 }) })
  console.log(`Saved ${values.out}`)
} finally {
  await browser.close()
}
