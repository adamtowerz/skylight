/**
 * Which pixels the cloud layer marches each frame, after Horizon Zero Dawn (Schneider 2015, "The
 * Real-time Volumetric Cloudscapes of Horizon Zero Dawn"). The scene target is tiled into square
 * cells and each frame only one pixel of every cell is marched; the scene pass reprojects the
 * rest from the cloud history (temporal.wgsl). Pixels take their turns in Bayer order, so any
 * two consecutive frames march pixels as far apart as a cell allows and every run of frames
 * covers the cell evenly.
 *
 * Each march is jittered by a blue-noise mask over the cells (`bluenoise.ts`) plus an offset
 * that is the same for the whole frame. The offset strides by the golden ratio at each visit, a
 * Weyl sequence, which spreads a pixel's successive jitters as evenly over [0, 1) as any sequence
 * can, so its average converges fast ("blue noise plus golden ratio", Wolfe et al. 2022,
 * "Spatiotemporal Blue Noise Masks", §2). Within one visit the pixels of a cell take offsets a
 * quarter apart, so the four of them are stratified too, and every frame's marches, one per cell,
 * keep the mask's blue spectrum.
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
  /** Added to the blue-noise mask for this frame's jitter, in [0, 1). */
  cloudJitter: number
}

/** 1/φ. */
const goldenRatio = (Math.sqrt(5) - 1) / 2

export function cloudSchedule(frame: number): CloudSchedule {
  const turns = cloudCell * cloudCell
  const turn = frame % turns
  const visit = Math.floor(frame / turns)
  return {
    cloudCell,
    cloudPhase: bayerPixel(turn, cloudCell),
    cloudJitter: (visit * goldenRatio + turn / turns) % 1,
  }
}
