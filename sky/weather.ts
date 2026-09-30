/**
 * The weather: what the sky holds besides the mood's flavour, as a pure function of simulated
 * time, so a given `?hour=` always shows the same sky and scrubbing the clock scrubs the weather.
 *
 * Every kind of weather comes and goes in spells. Each spell draws its own random amount (hashed
 * from its index, with a salt per kind so the kinds come and go independently), eased into the
 * next; spells are out of step with the day, so each twilight differs. A kind shows once its
 * spell's draw passes `forms`, and is whole by `whole`, so most spells bring none of it, some a
 * little, and a few the whole thing. The hour of day then lets it be there or not (`daily`), after
 * the physics that makes it: radiation fog in the cold small hours, haze on warm afternoons.
 *
 * Moods stay the per-twilight flavour (`moods.ts`); weather is layered on top of them.
 *
 * Adding a kind (e.g. a grey `deck` of nimbostratus, `precipitation` beneath it): give it a
 * field in `Weather` and an entry in `kinds` with its own salt, chosen so the opening seeds
 * (`seeds.ts`) keep their skies. A kind that depends on another (rain only under a deck) reads it
 * in `weatherAt`, after the independent kinds are drawn. Its uniforms go in `weatherUniforms`,
 * and `?name=` overrides it for free (`controls.ts`).
 */

import { lerp, smoothstep } from './math'
import type { Mood } from './moods'
import type { UniformValues } from './uniforms'

/** The weather at one moment, each 0 → 1. */
export interface Weather {
  /** How far a layer of altocumulus is there: the mood's `altocumulusCoverage` says how much sky it fills. */
  altocumulus: number
  /** Radiation fog around the observer: 0 none, 1 thick enough to hide the sun. */
  fog: number
  /** Aerosol near the ground, on top of the mood's: 1 triples it. */
  haze: number
}

interface Kind {
  /** Hours from one spell to the next. */
  spellHours: number
  /** Which spells are drawn: chosen so the opening seeds keep their skies. */
  salt: number
  /** The draw a spell needs before this weather shows, and by which it is whole. */
  forms: number
  whole: number
  /** How far the hour of day (0 → 24) lets it be there, 0 → 1. */
  daily: (hour: number) => number
}

/** Hours since `start` o'clock, in [0, 24). */
const since = (start: number, hour: number) => (((hour - start) % 24) + 24) % 24

const kinds: Record<keyof Weather, Kind> = {
  // Afternoon convection mixes the mid-levels dry; as it dies in the evening its moisture spreads
  // out into layers that linger through the night to dawn. So the layer is thinnest near midday.
  altocumulus: {
    spellHours: 13,
    salt: 261,
    forms: 0.5,
    whole: 0.9,
    daily: (hour) => 1 - 0.5 * Math.max(0, Math.cos(((hour - 13) / 12) * Math.PI)),
  },
  // Radiation fog: on a still, humid night the ground cools until the air on it condenses. It
  // forms after midnight, is thickest around sunrise (the coldest hour) and burns off in the
  // morning sun: 23:00 → 04:00 it thickens, 06:30 → 09:30 it lifts.
  fog: {
    spellHours: 17,
    salt: 23,
    forms: 0.5,
    // Most foggy mornings bring a mist the heaps glow through; only the rarest spell a thick bank.
    whole: 1.1,
    daily: (hour) => smoothstep(2, 7, since(21, hour)) * (1 - smoothstep(9.5, 12.5, since(21, hour))),
  },
  // Haze: warm afternoons stir dust, pollen and humid aerosols up into a deepening boundary layer;
  // it builds from mid-morning, lasts through the golden hour and settles out in the night.
  haze: {
    spellHours: 11,
    salt: 3432,
    forms: 0.5,
    whole: 0.9,
    daily: (hour) => smoothstep(10, 16, hour) * (1 - smoothstep(19.5, 23, hour)),
  },
}

export const weatherKinds = Object.keys(kinds) as (keyof Weather)[]

/** A random number in [0, 1) per spell (a murmur3-style integer mix). */
function draw(spell: number, salt: number) {
  let h = Math.imul(spell ^ salt, 0x9e3779b1)
  h = Math.imul(h ^ (h >>> 16), 0x85ebca6b)
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35)
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296
}

function presence({ spellHours, salt, forms, whole, daily }: Kind, hours: number) {
  const position = hours / spellHours
  const spell = Math.floor(position)
  const amount = lerp(draw(spell, salt), draw(spell + 1, salt), smoothstep(0, 1, position - spell))
  return smoothstep(forms, whole, amount) * daily(since(0, hours))
}

/** The weather at `hours` (simulated, since midnight of day zero). */
export function weatherAt(hours: number): Weather {
  return {
    altocumulus: presence(kinds.altocumulus, hours),
    fog: presence(kinds.fog, hours),
    haze: presence(kinds.haze, hours),
  }
}

/** How many times the mood's aerosols full haze adds, and how much higher it lifts them. */
const hazeAerosols = 2
const hazeHeight = 0.4

/** The mood with the weather's haze in its air: more aerosol, mixed higher by the warm afternoon. */
export function hazy(mood: Mood, haze: number): Mood {
  return {
    ...mood,
    aerosols: mood.aerosols * (1 + hazeAerosols * haze),
    aerosolHeight: mood.aerosolHeight * (1 + hazeHeight * haze),
  }
}

/**
 * Radiation fog, made physical: a layer of droplets on the ground, the eye inside it near the
 * bottom. Thicker fog is both deeper and denser: from a mist a few tens of metres deep that
 * softens the heaps to a 200 m bank (visibility 3.9 / extinction ≈ 400 m) through which only
 * the sun's disc and the brightest heaps still show: the sky is the point, so it never walls it off.
 */
const fogDepth = { thin: 0.06, thick: 0.2 } // km of fog above the eye
const thickFogExtinction = 10 // km⁻¹, grey: droplets are far larger than light's wavelengths

/** The weather's uniforms, besides the haze that goes into the mood's air (`hazy`). */
export function weatherUniforms({ altocumulus, fog }: Weather): Partial<UniformValues> {
  return {
    altocumulusPresence: altocumulus,
    fogDepth: lerp(fogDepth.thin, fogDepth.thick, fog),
    fogExtinction: thickFogExtinction * fog ** 0.7,
  }
}
