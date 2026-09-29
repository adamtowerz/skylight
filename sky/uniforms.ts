/**
 * The one `Uniforms` struct every shader sees, and its per-frame fill. Everything the GPU needs
 * from the CPU each frame lives here; everything else is computed in WGSL.
 */

import type { CameraBasis } from './camera'
import type { Celestial } from './celestial'
import type { History } from './history'
import { cloudSchedule } from './interleave'
import type { Vec2, Vec3 } from './math'
import { moodUniforms, weather, type Mood } from './moods'
import { struct, type Schema, type StructValues, type StructWriter } from './struct'

const schema = {
  // Frame
  resolution: 'vec2f', // scene target, px
  outputResolution: 'vec2f', // swap chain, px
  time: 'f32', // real seconds since start
  dt: 'f32', // real seconds since last frame, clamped
  reveal: 'f32', // 0 → 1 as the eyes open

  // Camera (world frame: x = east, y = up, z = north)
  cameraRight: 'vec3f',
  cameraUp: 'vec3f',
  cameraForward: 'vec3f',
  tanHalfFov: 'vec2f',
  previousCameraRight: 'vec3f', // last frame's camera, to reproject the cloud history
  previousCameraUp: 'vec3f',
  previousCameraForward: 'vec3f',
  previousCloudWind: 'vec2f', // last frame's wind offset, to follow the clouds' drift
  historyTrust: 'f32', // how far to trust the cloud history: 1 while the sky drifts, 0 starts afresh

  // Light
  sunDirection: 'vec3f',
  sunIlluminance: 'vec3f',
  moonDirection: 'vec3f',
  moonIlluminance: 'vec3f',
  skyRotation: 'mat4x4f', // celestial → local, for stars

  // Atmosphere (km, km⁻¹), after Hillaire 2020
  bottomRadius: 'f32',
  topRadius: 'f32',
  observerAltitude: 'f32',
  rayleighScattering: 'vec3f',
  rayleighScaleHeight: 'f32',
  mieScattering: 'vec3f',
  mieScaleHeight: 'f32',
  mieAbsorption: 'vec3f',
  mieAnisotropy: 'f32',
  ozoneAbsorption: 'vec3f',
  ozoneCenter: 'f32',
  groundAlbedo: 'vec3f',
  ozoneWidth: 'f32',
  nightGlow: 'vec3f', // airglow floor, so night is deep blue rather than black
  shaftStrength: 'f32', // amplification of the aerosols' forward scattering in sunlit beams

  // Clouds (km)
  cloudCoverage: 'f32',
  cloudDensity: 'f32',
  cloudTowers: 'f32', // how tall the heaps grow at the heart of the weather's convection cells
  cloudBottom: 'f32',
  cloudTop: 'f32',
  cloudWind: 'vec2f', // accumulated offset
  cloudEvolution: 'f32', // drift through the noise volume's third axis
  cirrusCoverage: 'f32',
  cirrusAltitude: 'f32',
  cloudCell: 'f32', // side of the cells the cloud layer marches one pixel of per frame, px
  cloudPhase: 'vec2f', // the pixel of every cell marched this frame
  cloudJitter: 'f32', // this frame's offset of the cloud march's blue-noise jitter

  // Post
  exposureBias: 'f32', // stops
  grain: 'f32',
  ditherLevels: 'f32',
  vignette: 'f32',
  paper: 'f32',
  blankColor: 'vec3f', // display-encoded page background the sky is revealed from
} as const satisfies Schema

export type UniformSchema = typeof schema
export type UniformValues = StructValues<UniformSchema>

export const Uniforms = struct('Uniforms', schema)

/** Prepended to every shader module: the struct and its one binding. */
export const uniformsWgsl = `${Uniforms.wgsl}\n@group(0) @binding(0) var<uniform> u: Uniforms;\n`

/** The look: film-like finishing, fixed across moods. */
const post = {
  exposureBias: 0,
  grain: 0.035,
  ditherLevels: 64,
  vignette: 0.35,
  paper: 0.018,
} as const satisfies Partial<UniformValues>

export interface FrameState {
  resolution: Vec2
  outputResolution: Vec2
  time: number
  dt: number
  /** Frames since start: whose turn it is to be marched. */
  frame: number
  reveal: number
  blankColor: Vec3
  /** Simulated hours since day zero; drives the weather. */
  hours: number
  camera: CameraBasis
  history: History
  sky: Celestial
  mood: Mood
}

export function fillUniforms(writer: StructWriter<UniformSchema>, state: FrameState) {
  const { camera, history, sky, mood, hours, frame, ...rest } = state
  writer.set({ ...rest, ...camera, ...history, ...sky, ...moodUniforms(mood), ...weather(hours), ...cloudSchedule(frame), ...post })
}
