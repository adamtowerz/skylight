/**
 * The CPU's part in the clouds' temporal accumulation (scene pass, temporal.wgsl): last frame's
 * camera, so the GPU can find where each view direction was, and how far to trust the average of
 * past frames. Not at all right after a resize; less and less as the clouds race by between frames,
 * which happens while time is scrubbed or sped up, so the sky never smears.
 */

import type { CameraBasis } from './camera'
import { naturalSeconds } from './clock'
import { smoothstep, type Vec3 } from './math'

/** Weight of the past while the sky drifts at its natural pace: an average over about ten frames. */
const steadyWeight = 0.9
/** Cloud drift between frames, in natural seconds (one is ≈ 30 m of wind), over which it fades. */
const fadeFrom = 0.25
const fadeTo = 2

export interface History {
  previousCameraRight: Vec3
  previousCameraUp: Vec3
  previousCameraForward: Vec3
  historyWeight: number
}

export interface HistoryTracker {
  /** This frame's reprojection and weight; remembers the camera and time for the next. */
  next(camera: CameraBasis, hours: number): History
  /** Forgets the past, e.g. when the render targets are recreated. */
  reset(): void
}

export function trackHistory(): HistoryTracker {
  let last: { camera: CameraBasis; seconds: number } | undefined

  return {
    next(camera, hours) {
      const seconds = naturalSeconds(hours)
      const previous = last
      last = { camera, seconds }
      const drift = previous ? Math.abs(seconds - previous.seconds) : Infinity
      const { cameraRight, cameraUp, cameraForward } = previous?.camera ?? camera
      return {
        previousCameraRight: cameraRight,
        previousCameraUp: cameraUp,
        previousCameraForward: cameraForward,
        historyWeight: steadyWeight * (1 - smoothstep(fadeFrom, fadeTo, drift)),
      }
    },

    reset() {
      last = undefined
    },
  }
}
