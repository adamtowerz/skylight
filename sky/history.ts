/**
 * The CPU's part in the clouds' temporal reconstruction (scene pass, temporal.wgsl): last frame's
 * camera and wind, so the GPU can find where the clouds along each view direction were, and how
 * far to trust the average of past frames. Not at all right after a resize; less and less as the clouds race by between frames,
 * which happens while time is scrubbed or sped up, so the sky never smears.
 */

import type { CameraBasis } from './camera'
import { naturalSeconds } from './clock'
import { smoothstep, type Vec2, type Vec3 } from './math'
import { windOffset } from './moods'

/** Cloud drift between frames, in natural seconds (one is ≈ 30 m of wind), over which it fades. */
const fadeFrom = 0.25
const fadeTo = 2

export interface History {
  previousCameraRight: Vec3
  previousCameraUp: Vec3
  previousCameraForward: Vec3
  previousCloudWind: Vec2
  historyTrust: number
}

export interface HistoryTracker {
  /** This frame's reprojection and trust; remembers the camera and time for the next. */
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
        previousCloudWind: windOffset(previous?.seconds ?? seconds),
        historyTrust: 1 - smoothstep(fadeFrom, fadeTo, drift),
      }
    },

    reset() {
      last = undefined
    },
  }
}
