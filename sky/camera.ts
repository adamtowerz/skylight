/**
 * Lying on the grass, looking up. The gaze rests well above the horizon, facing where the sun
 * sets, so the evening glow pools at the bottom of the frame while the sky turns overhead.
 * A slow breath and a hint of pointer parallax keep it alive.
 */

import { add, clamp, cross, normalize, radians, scale, TAU, type Vec2, type Vec3 } from './math'

const pitch = radians(62)
const verticalFov = radians(90)
/** Azimuth of sunset at our latitude and declination: west-northwest (x = east, z = north). */
const heading = radians(-70)
const breathPeriod = 6
const breathPitch = radians(0.3)
const breathRoll = radians(0.2)
const parallaxAngle = radians(1.5)
/** Pointer smoothing rate, per second. */
const parallaxRate = 1.5

export interface CameraBasis {
  cameraRight: Vec3
  cameraUp: Vec3
  cameraForward: Vec3
  tanHalfFov: Vec2
}

export interface Camera {
  update(dt: number, time: number): void
  /** Pointer position in [−1, 1]², y down. */
  point(x: number, y: number): void
  basis(aspect: number): CameraBasis
}

export function createCamera(reducedMotion: boolean): Camera {
  let time = 0
  const pointer = { x: 0, y: 0 }
  const parallax = { x: 0, y: 0 }

  return {
    update(dt, now) {
      time = now
      const follow = 1 - Math.exp(-parallaxRate * dt)
      parallax.x += (pointer.x - parallax.x) * follow
      parallax.y += (pointer.y - parallax.y) * follow
    },

    point(x, y) {
      if (reducedMotion) return
      pointer.x = clamp(x, -1, 1)
      pointer.y = clamp(y, -1, 1)
    },

    basis(aspect) {
      const breath = (TAU * time) / breathPeriod
      const sway = reducedMotion ? 0 : 1
      const yaw = heading + parallax.x * parallaxAngle
      const elevation = pitch + sway * breathPitch * Math.sin(breath) - parallax.y * parallaxAngle
      const roll = sway * breathRoll * Math.cos(breath)

      const forward: Vec3 = [
        Math.sin(yaw) * Math.cos(elevation),
        Math.sin(elevation),
        Math.cos(yaw) * Math.cos(elevation),
      ]
      const level = normalize(cross([0, 1, 0], forward))
      const tilt = cross(forward, level)
      const tanHalf = Math.tan(verticalFov / 2)
      return {
        cameraRight: add(scale(level, Math.cos(roll)), scale(tilt, Math.sin(roll))),
        cameraUp: add(scale(tilt, Math.cos(roll)), scale(level, -Math.sin(roll))),
        cameraForward: forward,
        tanHalfFov: [tanHalf * aspect, tanHalf],
      }
    },
  }
}
