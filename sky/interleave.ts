/**
 * Which pixels the cloud layer marches each frame, after Horizon Zero Dawn (Schneider 2015, "The
 * Real-time Volumetric Cloudscapes of Horizon Zero Dawn"). The scene target is tiled into square
 * cells and each frame only one pixel of every cell is marched; the scene pass reprojects the
 * rest from the cloud history (temporal.wgsl). Pixels take their turns in Bayer order, so any
 * two consecutive frames march pixels as far apart as a cell allows and every run of frames
 * covers the cell evenly.
 */

import type { Vec2 } from './math'

/** Cell side, px: a power of two. Each pixel is marched every `cloudCell`² frames. */
export const cloudCell = 2

/** The 2 × 2 Bayer order: diagonal first, then the other diagonal. */
const bayer: readonly Vec2[] = [
  [0, 0],
  [1, 1],
  [1, 0],
  [0, 1],
]

/**
 * The pixel of a cell of side `cell` visited `turn`-th. A cell is four quadrants: the two low bits
 * pick the quadrant in Bayer order, the rest the pixel within it, recursively.
 */
function bayerPixel(turn: number, cell: number): Vec2 {
  if (cell === 1) return [0, 0]
  const half = cell / 2
  const [x, y] = bayerPixel(turn >> 2, half)
  const [qx, qy] = bayer[turn & 3]
  return [x + qx * half, y + qy * half]
}

export interface CloudSchedule {
  cloudCell: number
  /** The pixel of every cell marched this frame. */
  cloudPhase: Vec2
  /** How many times each pixel has been marched before: strides its jitter. */
  cloudVisit: number
}

export function cloudSchedule(frame: number): CloudSchedule {
  const turns = cloudCell * cloudCell
  return {
    cloudCell,
    cloudPhase: bayerPixel(frame % turns, cloudCell),
    cloudVisit: Math.floor(frame / turns),
  }
}
