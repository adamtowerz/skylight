/**
 * The bright stars as the GPU reads them: the catalogue (`brightstars.ts`) decoded into `Star`s
 * (`seestar.wgsl`) in the J2000 equatorial frame, and binned into the cells of an equi-angular
 * cube map over the sky (`starfield.wgsl`). A star is listed in every cell its light reaches
 * (anywhere within `starReach` of it), so each pixel need look only at its own cell's stars.
 */

import { brightStars } from './brightstars'
import { add, clamp, cross, normalize, radians, scale, TAU, type Vec3 } from './math'

/** Cells per cube face edge, about 2.8° across. */
const catalogueCells = 32
/**
 * How far a star's light is drawn at most: its halo's extent (`STAR_EXTENT × STAR_HALO_WIDTH` in
 * `starlight.wgsl`), or its core's in a window a few hundred pixels tall.
 */
const starReach = radians(1.5)
/** Points around each star's reach at which to look for the cells it touches. */
const reachSamples = 24

/** Cells per cube face edge of the procedural faint field (`faintstars.wgsl`), about 0.7° across. */
const faintFieldCells = 128

/**
 * Generated constants for the star shaders (`seenstars.wgsl`, `starfield.wgsl`), so the binning,
 * the buffers' layout and the lookups can't disagree.
 */
export const starLayoutWgsl = (count: number) =>
  `const CATALOGUE_STARS = ${count}u;\nconst CATALOGUE_CELLS = ${catalogueCells}u;\nconst FIELD_CELLS = ${faintFieldCells}u;\n`

/** Slots of the seen-star buffer: the catalogue's stars, then one per faint-field cell. */
export const seenStarSlots = (count: number) => count + 6 * faintFieldCells * faintFieldCells

interface StarCatalogue {
  count: number
  /** `Star`s, brightest first: direction (xyz), V, B − V, padded to 8 floats. */
  stars: Float32Array<ArrayBuffer>
  /** Per cell, the index of its first entry, then one past the last cell's last. */
  cells: Uint32Array<ArrayBuffer>
  /** Star indices, cell after cell. */
  entries: Uint32Array<ArrayBuffer>
}

/** Bytes per WGSL `SeenStar`: a vec2f, an f32, then a vec3f aligned to 16. */
export const seenStarSize = 32

/** Mirrors `cubePoint` in `cubemap.wgsl`, down to the cell. */
function cubeCell(dir: Vec3): number {
  const [ax, ay, az] = dir.map(Math.abs)
  const axis = ax >= ay && ax >= az ? 0 : ay >= az ? 1 : 2
  const major = dir[axis]
  const cell = (t: number) => clamp(Math.floor((Math.atan(t / Math.abs(major)) / (Math.PI / 2) + 0.5) * catalogueCells), 0, catalogueCells - 1)
  const face = 2 * axis + (major < 0 ? 1 : 0)
  return (face * catalogueCells + cell(dir[(axis + 2) % 3])) * catalogueCells + cell(dir[(axis + 1) % 3])
}

/** Every cell within `starReach` of `dir`: its own, and those met around the circle of its reach. */
function cellsReached(dir: Vec3): Set<number> {
  const side = normalize(cross(dir, Math.abs(dir[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0]))
  const up = cross(dir, side)
  const cells = new Set([cubeCell(dir)])
  for (let i = 0; i < reachSamples; i++) {
    const angle = (TAU * i) / reachSamples
    const around = add(scale(side, Math.cos(angle)), scale(up, Math.sin(angle)))
    cells.add(cubeCell(add(scale(dir, Math.cos(starReach)), scale(around, Math.sin(starReach)))))
  }
  return cells
}

export function starCatalogue(): StarCatalogue {
  const bytes = Uint8Array.from(atob(brightStars), (char) => char.charCodeAt(0))
  const data = new DataView(bytes.buffer)
  const count = bytes.length / 6
  const bins: number[][] = Array.from({ length: 6 * catalogueCells * catalogueCells }, () => [])
  const stars = new Float32Array(8 * count)
  for (let i = 0; i < count; i++) {
    const ra = (data.getUint16(6 * i, true) / 65536) * TAU
    const dec = (data.getInt16(6 * i + 2, true) / 32767) * (Math.PI / 2)
    const direction: Vec3 = [Math.cos(dec) * Math.cos(ra), Math.cos(dec) * Math.sin(ra), Math.sin(dec)]
    stars.set([...direction, data.getUint8(6 * i + 4) / 25 - 2, data.getUint8(6 * i + 5) / 64 - 0.5], 8 * i)
    for (const cell of cellsReached(direction)) bins[cell].push(i)
  }

  const cells = new Uint32Array(bins.length + 1)
  bins.forEach((bin, cell) => (cells[cell + 1] = cells[cell] + bin.length))
  return { count, stars, cells, entries: Uint32Array.from(bins.flat()) }
}
