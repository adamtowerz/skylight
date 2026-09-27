/**
 * The few scalar and vector helpers the CPU side needs. Vectors are plain readonly tuples so
 * they can be handed straight to the uniform writer.
 */

export type Vec2 = readonly [number, number]
export type Vec3 = readonly [number, number, number]
export type Vec4 = readonly [number, number, number, number]
/** Column-major, matching WGSL's `mat4x4f`. */
export type Mat4 = readonly [
  number, number, number, number,
  number, number, number, number,
  number, number, number, number,
  number, number, number, number,
]

export const TAU = Math.PI * 2

export const radians = (degrees: number) => (degrees * Math.PI) / 180

export const clamp = (x: number, min: number, max: number) => Math.min(Math.max(x, min), max)

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t

export function smoothstep(edge0: number, edge1: number, x: number) {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
  return t * t * (3 - 2 * t)
}

export const add = (a: Vec3, b: Vec3): Vec3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

export const scale = (v: Vec3, s: number): Vec3 => [v[0] * s, v[1] * s, v[2] * s]

/** Component-wise product. */
export const multiply = (a: Vec3, b: Vec3): Vec3 => [a[0] * b[0], a[1] * b[1], a[2] * b[2]]

export const dot = (a: Vec3, b: Vec3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

export const cross = (a: Vec3, b: Vec3): Vec3 => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
]

export const normalize = (v: Vec3): Vec3 => scale(v, 1 / Math.hypot(v[0], v[1], v[2]))

/** A rotation matrix whose columns are the given orthonormal basis vectors. */
export const basisMatrix = (x: Vec3, y: Vec3, z: Vec3): Mat4 => [
  x[0], x[1], x[2], 0,
  y[0], y[1], y[2], 0,
  z[0], z[1], z[2], 0,
  0, 0, 0, 1,
]
