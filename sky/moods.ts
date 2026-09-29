/**
 * Moods: art direction by amplifying physical parameters, never by painting colour on top.
 * Each mood is a set of multipliers on Earth's atmosphere plus cloud cover. Every twilight
 * gets the next mood, and the change crossfades through midday and deep night, so no two
 * sunsets look alike.
 */

import { naturalSeconds } from './clock'
import { lerp, multiply, scale, smoothstep, type Vec2, type Vec3 } from './math'
import type { UniformValues } from './uniforms'

/** The sun above the atmosphere, in the arbitrary HDR units the whole pipeline is exposed for. */
const sunIlluminance: Vec3 = [20, 19.6, 18.8]

/**
 * Earth's clear-sky atmosphere, from Hillaire 2020 (km, km⁻¹): Rayleigh and Mie scattering,
 * the ozone absorption layer (a tent centred at 25 km, 30 km wide), and a grassy ground.
 * Mie anisotropy (Earth: g = 0.8) and the aerosols' spectral slope are set per mood.
 */
const earth = {
  bottomRadius: 6360,
  topRadius: 6460,
  observerAltitude: 0.2,
  rayleighScattering: [5.802e-3, 13.558e-3, 33.1e-3],
  rayleighScaleHeight: 8,
  mieScattering: [3.996e-3, 3.996e-3, 3.996e-3],
  mieAbsorption: [0.444e-3, 0.444e-3, 0.444e-3],
  mieScaleHeight: 1.2,
  ozoneAbsorption: [0.65e-3, 1.881e-3, 0.085e-3],
  ozoneCenter: 25,
  ozoneWidth: 30,
  groundAlbedo: [0.25, 0.3, 0.2],
  nightGlow: [0.0006, 0.0009, 0.002],
  cloudBottom: 1.5,
  cloudTop: 3.5,
  cirrusAltitude: 8,
} as const satisfies Partial<UniformValues>

export interface Mood {
  /** Multiplier on Rayleigh scattering: deeper blues, redder sunsets. */
  rayleigh: number
  /** Multiplier on aerosol density: haze, glow around the sun, golden light. */
  aerosols: number
  /** Multiplier on the aerosol scale height: how high the haze reaches. */
  aerosolHeight: number
  /**
   * Ångström exponent α of the aerosols (extinction ∝ λ^−α, Hillaire's Earth: 0). Fine smoke
   * and haze (α ≈ 1.3) scatter blue more than red, reddening the sun and its glow; large
   * droplets (α ≈ 0) are grey.
   */
  aerosolAngstrom: number
  /** Mie phase anisotropy g: how tightly the haze glows around the sun. */
  mieAnisotropy: number
  /**
   * Spectral slope of the sunlight entering the atmosphere (illuminance ∝ λ^warmth): the
   * reddening of haze and smoke far beyond the modelled column. Gold light, golden glow.
   */
  sunWarmth: number
  /** Multiplier on ozone absorption: the violet-blue of the hour after sunset. */
  ozone: number
  /**
   * Multiplier on the aerosols' forward scattering in air lit through the gaps between the heaps:
   * how bright the light shafts are (0: none beyond what the sky-view LUT holds).
   */
  shafts: number
  cloudCoverage: number
  cloudDensity: number
  /**
   * How tall the heaps grow where convection is strongest, at the heart of the weather's cells:
   * 0 keeps them fair-weather cumulus, 1 lets them tower into congestus that fill the layer.
   */
  cloudTowers: number
  cirrusCoverage: number
}

const moods = {
  goldenHaze: {
    rayleigh: 1.15,
    aerosols: 3.5,
    aerosolHeight: 1.2,
    aerosolAngstrom: 0.5,
    mieAnisotropy: 0.84,
    sunWarmth: 0.7,
    ozone: 1.3,
    shafts: 300,
    cloudCoverage: 0.3,
    cloudDensity: 0.7,
    cloudTowers: 0.4,
    cirrusCoverage: 0.4,
  },
  violetDusk: {
    rayleigh: 1.3,
    aerosols: 0.8,
    aerosolHeight: 1,
    aerosolAngstrom: 0.8,
    mieAnisotropy: 0.8,
    sunWarmth: 0,
    ozone: 2.6,
    shafts: 500,
    cloudCoverage: 0.2,
    cloudDensity: 0.6,
    cloudTowers: 0.15,
    cirrusCoverage: 0.45,
  },
  emberSky: {
    rayleigh: 1.2,
    aerosols: 2.5,
    aerosolHeight: 1.3,
    aerosolAngstrom: 1.2,
    mieAnisotropy: 0.85,
    sunWarmth: 0.9,
    ozone: 1.6,
    shafts: 300,
    cloudCoverage: 0.45,
    cloudDensity: 1,
    cloudTowers: 0.9,
    cirrusCoverage: 0.3,
  },
  clear: {
    rayleigh: 1,
    aerosols: 1,
    aerosolHeight: 1,
    aerosolAngstrom: 0.6,
    mieAnisotropy: 0.8,
    sunWarmth: 0,
    ozone: 1,
    shafts: 500,
    cloudCoverage: 0.15,
    cloudDensity: 0.6,
    cloudTowers: 0,
    cirrusCoverage: 0.2,
  },
  softOvercast: {
    rayleigh: 1,
    aerosols: 4,
    aerosolHeight: 1.5,
    aerosolAngstrom: 0.3,
    mieAnisotropy: 0.75,
    sunWarmth: 0.3,
    ozone: 1,
    shafts: 210,
    cloudCoverage: 0.7,
    cloudDensity: 0.55,
    cloudTowers: 0.6,
    cirrusCoverage: 0.1,
  },
} as const satisfies Record<string, Mood>

const sequence: readonly Mood[] = Object.values(moods)

const moodAt = (index: number) => sequence[((index % sequence.length) + sequence.length) % sequence.length]

function blend(a: Mood, b: Mood, t: number): Mood {
  const mixed = { ...a }
  for (const key of Object.keys(a) as (keyof Mood)[]) mixed[key] = lerp(a[key], b[key], t)
  return mixed
}

/** Twilights (06:00 and 18:00) counted from midnight of day zero; fractional in between. */
const twilights = (hours: number) => (hours - 6) / 12

/**
 * The mood cycle, anchored so that the twilight nearest `startHours` shows mood number
 * `first`. Moods hold steady through each twilight and crossfade around noon and midnight.
 */
export function moodCycle(startHours: number, first = 0) {
  const offset = first - Math.round(twilights(startHours))
  return (hours: number): Mood => {
    const position = twilights(hours) + offset
    const index = Math.floor(position)
    return blend(moodAt(index), moodAt(index + 1), smoothstep(0.25, 0.75, position - index))
  }
}

/** The wavelengths (nm) Hillaire's RGB coefficients are sampled at, and the reference for α. */
const wavelengths: Vec3 = [680, 550, 440]
const referenceWavelength = 550

/** The power law (λ / 550 nm)^−α at those wavelengths: aerosol extinction, or a sun's tint. */
function angstrom(alpha: number): Vec3 {
  const relative = (wavelength: number) => (wavelength / referenceWavelength) ** -alpha
  return [relative(wavelengths[0]), relative(wavelengths[1]), relative(wavelengths[2])]
}

/** A mood made physical: Earth's atmosphere scaled by the mood's multipliers. */
export function moodUniforms(mood: Mood): Partial<UniformValues> {
  const aerosols = scale(angstrom(mood.aerosolAngstrom), mood.aerosols)
  return {
    ...earth,
    sunIlluminance: multiply(sunIlluminance, angstrom(-mood.sunWarmth)),
    rayleighScattering: scale(earth.rayleighScattering, mood.rayleigh),
    mieScattering: multiply(earth.mieScattering, aerosols),
    mieAbsorption: multiply(earth.mieAbsorption, aerosols),
    mieScaleHeight: earth.mieScaleHeight * mood.aerosolHeight,
    mieAnisotropy: mood.mieAnisotropy,
    ozoneAbsorption: scale(earth.ozoneAbsorption, mood.ozone),
    shaftStrength: mood.shafts,
    cloudCoverage: mood.cloudCoverage,
    cloudDensity: mood.cloudDensity,
    cloudTowers: mood.cloudTowers,
    cirrusCoverage: mood.cirrusCoverage,
  }
}

/**
 * Prevailing wind (km per real second at the natural pace; x = east, z = north), a time-lapse of
 * a westerly: clouds rise out of the sunset glow and drift overhead. And how fast they boil and
 * reform (km per second through the noise volume).
 */
const wind: Vec2 = [0.03, -0.012]
const evolutionPerSecond = 0.0025

/** How far the wind has carried the clouds after `seconds` of natural time, km. */
export const windOffset = (seconds: number): Vec2 => [wind[0] * seconds, wind[1] * seconds]

/**
 * Cloud motion as a pure function of simulated time, so scrubbing the clock scrubs the clouds
 * too and a given `?hour=` always shows the same sky. It runs on the clock's natural seconds,
 * so the drift looks equally calm at noon and at sunset.
 */
export function weather(hours: number): Partial<UniformValues> {
  const seconds = naturalSeconds(hours)
  return {
    cloudWind: windOffset(seconds),
    cloudEvolution: evolutionPerSecond * seconds,
  }
}
