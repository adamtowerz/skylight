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
 * Some kinds depend on others, and are worked out from them in `weatherAt` after the independent
 * kinds are drawn (and any held by `?name=`): rain falls only from a thick deck, and a deck, by
 * keeping the ground from cooling under a clear sky, allows no radiation fog.
 *
 * Thunderstorms are drawn by the day instead (`stormOf`): about one warm afternoon or evening in
 * eleven brings one, an hour to three of it. It is not a spell everywhere at once but a thing that
 * passes: its deck, its core and their edges ride in on the wind, so it is a field across the sky
 * (`storm.wgsl`), and what the eye lies under is that field where it lies. It closes the deck in
 * ahead of it, rains lightly as it comes and goes, and pours under its core.
 *
 * Adding a kind: give it a field in `Weather` and, if it is independent, an entry in `kinds` with
 * its own salt, chosen so the opening seeds (`seeds.ts`) keep their skies. Its uniforms go in
 * `weatherUniforms`, and `?name=` holds it for free (`controls.ts`).
 */

import { lerp, smoothstep, type Vec4 } from './math'
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
  /** A low grey deck of stratus and nimbostratus: 0.4 broken, with gaps; 1 the whole sky. */
  deck: number
  /** Light rain from the deck: 1 is `lightRain` mm/h, the lead-in and the tail of a storm. */
  precipitation: number
  /** A thunderstorm's core overhead: 1 its heaviest, a torrent under a nimbostratus base. */
  storm: number
  /** The storm as a field across the sky, which the eye sees pass. */
  front: StormFront
}

/** The kinds of weather, each 0 → 1, that `?name=` can hold. */
export type WeatherKind = Exclude<keyof Weather, 'front'>
export type HeldWeather = Partial<Record<WeatherKind, number>>

/** The kinds drawn on their own; the rest follow from them. */
type Independent = Exclude<WeatherKind, 'precipitation' | 'storm'>

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

const kinds: Record<Independent, Kind> = {
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
  // A rain deck comes in on a front, whatever the hour: a grey day or night of it about once a
  // week, broken at its edges, lasting from a few hours to a day.
  deck: {
    spellHours: 19,
    salt: 1368,
    forms: 0.72,
    whole: 0.95,
    daily: () => 1,
  },
}

/** Showers come and go under a deck in spells of their own, a few hours long. */
const showers: Kind = {
  spellHours: 5,
  salt: 11,
  forms: 0.35,
  whole: 0.75,
  daily: () => 1,
}
/** How thick the deck must be before it rains: only nimbostratus rains, not a broken stratocumulus. */
const rainingDeck = { from: 0.6, to: 0.9 }

export const weatherKinds: readonly WeatherKind[] = [...(Object.keys(kinds) as Independent[]), 'precipitation', 'storm']

/**
 * Thunderstorms grow out of the heat of the day: on about one day in eleven (`chance`) one
 * passes, its core arriving between `arrives` o'clock, lasting `lasts` hours and as fierce as
 * `peak`. Which days, and when, are hashed from the day with `salt`, chosen so that no opening
 * seed's day brings one.
 */
const storms = { salt: 27, chance: 0.09, arrives: [15.5, 19.5], lasts: [1, 3], peak: [0.7, 1] } as const
/**
 * How a storm passes, in hours from its core's arrival (`a`) and departure (`d`): the deck closes in
 * ahead of it and breaks up behind it; light rain leads in and trails off; the core comes in
 * abruptly behind its gust front and eases off.
 */
const stormDeck = { closes: [-1.3, -0.6], breaks: [0.3, 1.0] } as const
const stormDrizzle = { starts: [-0.45, -0.1], stops: [-0.1, 0.5] } as const
const stormCore = { arrives: [-0.15, 0], leaves: [-0.25, 0.15] } as const
/**
 * How fast the storm crosses the sky, km per simulated hour. The clock is a time-lapse, so this is
 * not the storm's speed over the ground but the pace at which its edges sweep over the low deck,
 * slow enough to see the shelf roll overhead.
 */
const stormSweep = 3
/**
 * The clock lingers as a storm passes, as it does at twilight: fully from a little before the core
 * arrives to a little after it leaves, eased in and out over `in` and `out`, hours from them
 * (`clock.ts` sets how slowly).
 */
const stormLingering = { in: [-1, -0.2], out: [0.2, 1] } as const

/**
 * Where the storm's core and the deck it brings begin and end along the wind, km upwind of the eye
 * (each a window: in from x to y, out from z to w; `storm.wgsl`), and how fierce it is at its heart.
 */
interface StormFront {
  peak: number
  core: Vec4
  deck: Vec4
  /** The deck's cover away from the storm: the weather's own. */
  around: number
}

interface Storm {
  arrives: number
  leaves: number
  peak: number
}

/** The storm of day `day`, if it brings one, in hours since midnight of day zero. */
function stormOf(day: number): Storm | undefined {
  const { salt, chance, arrives, lasts, peak } = storms
  if (draw(4 * day, salt) >= chance) return undefined
  const arrival = 24 * day + lerp(arrives[0], arrives[1], draw(4 * day + 1, salt))
  return {
    arrives: arrival,
    leaves: arrival + lerp(lasts[0], lasts[1], draw(4 * day + 2, salt)),
    peak: lerp(peak[0], peak[1], draw(4 * day + 3, salt)),
  }
}

/** A window over time: it opens over `in`, hours from the storm's arrival, and closes over `out`, hours from its departure. */
type Window = { in: readonly [number, number]; out: readonly [number, number] }

/** A window's edges as km upwind of the eye at `hours`, for the GPU. */
function edges(storm: Storm, { in: rise, out: fall }: Window, hours: number): Vec4 {
  const km = (hour: number) => (hour - hours) * stormSweep
  return [km(storm.arrives + rise[0]), km(storm.arrives + rise[1]), km(storm.leaves + fall[0]), km(storm.leaves + fall[1])]
}

/** How far a window, given as km edges, is open at `x` km upwind. */
const open = ([a, b, c, d]: Vec4, x: number) => smoothstep(a, b, x) * (1 - smoothstep(c, d, x))

const always: Vec4 = [-1e5, -1e5 + 1, 1e5, 1e5 + 1]
const windows = {
  core: { in: stormCore.arrives, out: stormCore.leaves },
  deck: { in: stormDeck.closes, out: stormDeck.breaks },
  drizzle: { in: stormDrizzle.starts, out: stormDrizzle.stops },
} as const

/**
 * The storm passing at `hours`, or held at `held` all over the sky: its field (`front`), and at
 * the eye its core, the deck it brings and its light rain.
 */
function stormAt(hours: number, held?: number) {
  const storm = held === undefined ? stormOf(Math.floor(hours / 24)) : undefined
  const front = storm
    ? { peak: storm.peak, core: edges(storm, windows.core, hours), deck: edges(storm, windows.deck, hours) }
    : { peak: held ?? 0, core: always, deck: always }
  const drizzle = storm ? open(edges(storm, windows.drizzle, hours), 0) : 1
  const brings = smoothstep(0, 0.2, front.peak)
  return { front, core: front.peak * open(front.core, 0), deck: brings * open(front.deck, 0), drizzle: brings * drizzle }
}

/**
 * How fully the clock lingers at `hours` for a passing storm (0 away from one, 1 under it), and
 * since when it has been slowing: the start of that day's lingering.
 */
export function stormLingers(hours: number): { lingering: number; since: number } {
  const day = Math.floor(hours / 24)
  const storm = stormOf(day)
  if (!storm) return { lingering: 0, since: 24 * day }
  return { lingering: open(edges(storm, stormLingering, hours), 0), since: storm.arrives + stormLingering.in[0] }
}

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

/**
 * The weather at `hours` (simulated, since midnight of day zero), with any kinds `held` at a
 * value whatever the timeline says; the kinds that follow from others follow the held ones too.
 */
export function weatherAt(hours: number, held: HeldWeather = {}): Weather {
  const storm = stormAt(hours, held.storm)
  const around = held.deck ?? presence(kinds.deck, hours)
  const deck = Math.max(around, storm.deck)
  const showering = presence(showers, hours) * smoothstep(rainingDeck.from, rainingDeck.to, deck)
  return {
    altocumulus: held.altocumulus ?? presence(kinds.altocumulus, hours),
    fog: held.fog ?? presence(kinds.fog, hours) * (1 - deck),
    haze: held.haze ?? presence(kinds.haze, hours),
    deck,
    precipitation: held.precipitation ?? Math.max(showering, storm.drizzle),
    storm: storm.core,
    front: { ...storm.front, around },
  }
}

/** How many times the mood's aerosols full haze adds, and how much higher it lifts them. */
const hazeAerosols = 2
const hazeHeight = 0.4
/** The share of the aerosols light rain washes out. */
const rainWashout = 0.5

/**
 * The mood with the weather in its air: haze adds aerosol, mixed higher by the warm afternoon; a
 * rain deck comes in on a front of clean air, so as it closes in the far haze and smoke that redden the sunlight
 * go, and the rain washes the aerosols out of the air beneath it.
 */
export function weathered(mood: Mood, { haze, deck, precipitation }: Weather): Mood {
  return {
    ...mood,
    aerosols: mood.aerosols * (1 + hazeAerosols * haze) * (1 - rainWashout * precipitation),
    aerosolHeight: mood.aerosolHeight * (1 + hazeHeight * haze),
    sunWarmth: mood.sunWarmth * (1 - deck * deck),
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

/**
 * The deck, made physical. As it comes in it covers more of the sky, lowers and thickens: from a
 * broken stratocumulus at 1.2 km, in rows of cells grey at their hearts (optical depth about 17 on
 * average) and thinning to wisps at their edges, to the unbroken nimbostratus of a rainy day at
 * 600 m, about forty deep.
 */
const deckBase = { broken: 1.2, whole: 0.6 } // km
const deckDepth = { broken: 17, whole: 42 }
/** Light rain, mm/h: what `precipitation` 1 brings (light rain is up to 2.5 mm/h). */
const lightRain = 2
/**
 * A storm's core: the foot of a cumulonimbus, far deeper than a rainy day's deck (optical depth
 * about 700, the column of a tower some 9 km tall), lower by up to `stormLowers` km, pouring rain
 * up to `heavyRain` mm/h at its fiercest (a torrential downpour), as the square of how fierce: a
 * weak storm only rains hard.
 */
const stormDepth = 700
const stormLowers = 0.15
const heavyRain = 45

/** Rain at the eye, mm/h, before the gusts. */
export const rainRate = ({ precipitation, storm }: Weather) => lightRain * precipitation + heavyRain * storm * storm

/** The weather's uniforms, besides what goes into the mood's air (`weathered`). */
export function weatherUniforms({ altocumulus, fog, deck, precipitation, storm, front }: Weather): Partial<UniformValues> {
  return {
    altocumulusPresence: altocumulus,
    fogDepth: lerp(fogDepth.thin, fogDepth.thick, fog),
    fogExtinction: thickFogExtinction * fog ** 0.7,
    deckCover: front.around,
    deckBase: lerp(deckBase.broken, deckBase.whole, deck) - stormLowers * storm,
    deckDepth: lerp(deckDepth.broken, deckDepth.whole, deck),
    rainRate: lightRain * precipitation,
    stormPeak: front.peak,
    stormCore: front.core,
    stormDeck: front.deck,
    stormDepth,
    stormRain: heavyRain * front.peak * front.peak,
  }
}
