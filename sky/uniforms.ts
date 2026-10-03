/**
 * The one `Uniforms` struct every shader sees, and its per-frame fill. Everything the GPU needs
 * from the CPU each frame lives here; everything else is computed in WGSL.
 */

import type { CameraBasis } from './camera'
import type { Celestial } from './celestial'
import type { History } from './history'
import { cloudSchedule } from './interleave'
import type { Vec2, Vec3 } from './math'
import { eyeDropSlots } from './eyedrops'
import type { Gusts } from './gusts'
import { drift, moodUniforms, type Mood } from './moods'
import { struct, type Schema, type StructValues, type StructWriter } from './struct'
import { weathered, weatherUniforms, type Weather } from './weather'

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
  altocumulusCoverage: 'f32', // when the weather brings it
  altocumulusPresence: 'f32', // how far it does, 0 → 1
  altocumulusSheet: 'f32', // 0: a mackerel sky of separate cloudlets, 1: merged into altostratus
  altocumulusAltitude: 'f32', // middle of the layer
  cirrusCoverage: 'f32',
  cirrusAltitude: 'f32',
  cloudCell: 'f32', // side of the cells the cloud layer marches one pixel of per frame, px
  cloudPhase: 'vec2f', // the pixel of every cell marched this frame
  cloudJitter: 'f32', // this frame's offset of the cloud march's blue-noise jitter

  // Fog (km, km⁻¹): a layer of droplets on the ground, the eye inside it
  fogDepth: 'f32', // of fog above the eye, on average
  fogExtinction: 'f32', // grey
  fogWind: 'vec2f', // accumulated offset of its wisps
  fogChurn: 'f32', // drift of its thickness through the noise's third axis

  // Deck and rain (km, mm/h): a low grey deck of stratus and nimbostratus, and the rain from it
  deckCover: 'f32', // share of the sky it covers, away from a storm
  deckBase: 'f32', // height of its base, on average
  deckDepth: 'f32', // optical depth of its columns where whole, on average
  rainRate: 'f32', // light rain, all over the deck

  // A thunderstorm passing over, a field across the sky (storm.wgsl; km upwind of the eye)
  stormPeak: 'f32', // how fierce at its heart, 0 → 1
  stormCore: 'vec4f', // its core's window: in from x to y, out from z to w
  stormDeck: 'vec4f', // the window of the deck it brings
  stormDepth: 'f32', // optical depth of its base at its heart
  stormRain: 'f32', // mm/h at its heart
  stormWind: 'vec2f', // the heaps' wind offset as cloudWind, but on the clock's seconds (clock.ts)
  stormChurn: 'f32', // cloudEvolution likewise

  // Rain near the eye (m/s, m), and the drops on it (eyedrops.ts)
  rainGust: 'f32', // what the gusts make of the rain rate
  rainWind: 'vec2f',
  rainFallSpeed: 'f32', // terminal, through the air
  rainFallen: 'f32', // along the slant, folded
  eyeDrops: `array<vec4f, ${eyeDropSlots}>`, // per drop: uv of its centre, radius (view heights), strength

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
  /** Simulated hours since day zero; drives the drift of clouds and fog. */
  hours: number
  weather: Weather
  camera: CameraBasis
  history: History
  sky: Celestial
  mood: Mood
  /** The rain near the eye this frame: its gusts, how far it has fallen, the drops on the eye. */
  rain: Gusts & { rainFallen: number; rainFallSpeed: number; eyeDrops: number[] }
}

export function fillUniforms(writer: StructWriter<UniformSchema>, state: FrameState) {
  const { camera, history, sky, mood, weather, rain, hours, frame, ...rest } = state
  writer.set({
    ...rest,
    ...camera,
    ...history,
    ...sky,
    ...moodUniforms(weathered(mood, weather)),
    ...weatherUniforms(weather),
    ...drift(hours),
    ...cloudSchedule(frame),
    ...rain,
    ...post,
  })
}
