#!/usr/bin/env node
/**
 * Generates `sky/brightstars.ts`: every star of the Yale Bright Star Catalogue, 5th revised
 * edition (Hoffleit & Warren 1991, CDS catalogue V/50, public domain), down to visual magnitude
 * 5.5, packed into 6 bytes each, brightest first:
 *
 *   u16 right ascension (J2000) · 2¹⁶ / 360°     i16 declination (J2000) · 32767 / 90°
 *   u8  (V + 2) · 25                              u8  (B − V + 0.5) · 64
 *
 * The real sky's brightest few thousand stars are what draws the constellations; the fainter
 * multitude beneath them is procedural (`starfield.wgsl`). A handful of stars (components of
 * doubles) have no B − V; theirs is estimated from the spectral class.
 *
 *   node scripts/stars.mjs [catalog file]   # default: downloads catalog.gz from CDS
 */

import { writeFileSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { gunzipSync } from 'node:zlib'

const source = 'https://cdsarc.cds.unistra.fr/ftp/V/50/catalog.gz'
const faintest = 5.5
/** Typical B − V of main-sequence stars by spectral class (Allen's Astrophysical Quantities). */
const colorByClass = { O: -0.3, B: -0.15, A: 0.1, F: 0.4, G: 0.7, K: 1.15, M: 1.6 }

const path = process.argv[2]
const text = path ? await readFile(path, 'latin1') : gunzipSync(Buffer.from(await (await fetch(source)).arrayBuffer())).toString('latin1')

/** Fixed-width field, 1-based inclusive byte columns as in the catalogue's ReadMe. */
const field = (line, from, to) => line.slice(from - 1, to).trim()

const stars = text
  .split('\n')
  .filter((line) => field(line, 76, 77) && field(line, 103, 107))
  .map((line) => {
    const ra = 15 * (Number(field(line, 76, 77)) + Number(field(line, 78, 79)) / 60 + Number(field(line, 80, 83)) / 3600)
    const sign = field(line, 84, 84) === '-' ? -1 : 1
    const dec = sign * (Number(field(line, 85, 86)) + Number(field(line, 87, 88)) / 60 + Number(field(line, 89, 90)) / 3600)
    const spectralClass = field(line, 128, 147).match(/[OBAFGKM]/)?.[0] ?? 'G'
    const bv = field(line, 110, 114)
    return { ra, dec, v: Number(field(line, 103, 107)), bv: bv ? Number(bv) : colorByClass[spectralClass] }
  })
  .filter((star) => star.v <= faintest)
  .sort((a, b) => a.v - b.v)

const clampByte = (x) => Math.max(0, Math.min(255, Math.round(x)))
const bytes = new DataView(new ArrayBuffer(stars.length * 6))
stars.forEach(({ ra, dec, v, bv }, i) => {
  bytes.setUint16(6 * i, Math.round((ra / 360) * 65536) % 65536, true)
  bytes.setInt16(6 * i + 2, Math.round((dec / 90) * 32767), true)
  bytes.setUint8(6 * i + 4, clampByte((v + 2) * 25))
  bytes.setUint8(6 * i + 5, clampByte((bv + 0.5) * 64))
})

const base64 = Buffer.from(bytes.buffer).toString('base64')
writeFileSync(
  new URL('../sky/brightstars.ts', import.meta.url),
  `/**
 * The ${stars.length} stars of the Yale Bright Star Catalogue (5th revised ed., Hoffleit & Warren 1991,
 * public domain) down to V = ${faintest}, packed by \`scripts/stars.mjs\` (which documents the layout).
 * Generated: do not edit.
 */

export const brightStars = '${base64}'
`,
)
console.log(`${stars.length} stars, ${bytes.byteLength} bytes`)
