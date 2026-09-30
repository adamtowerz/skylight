/**
 * Whether there is altocumulus at all: mid-level moisture comes and goes with the weather, so most
 * skies have none, some a patch, and now and then one has a whole mackerel sky. Each spell of
 * weather draws its own moisture, eased into the next, and the mood's `altocumulusCoverage` says
 * how much of the sky the layer fills when it is fully there. It is a pure function of simulated
 * time, like the wind, so a given `?hour=` always shows the same sky.
 */

import { lerp, smoothstep } from './math'

/** Hours from one spell of weather to the next: out of step with the twilights, so each differs. */
const spellHours = 13
/** Which spells are drawn: chosen so the opening seeds keep their open skies but one. */
const salt = 261
/** The moisture a spell needs before altocumulus forms, and by which it is whole. */
const forms = 0.5
const whole = 0.9
/**
 * Afternoon convection mixes the mid-levels dry; as it dies in the evening its moisture spreads out
 * into layers that linger through the night to dawn. So the layer is thinnest near midday.
 */
const middayThinning = 0.5

/** A random number in [0, 1) per spell (a murmur3-style integer mix). */
function draw(spell: number) {
  let h = Math.imul(spell ^ salt, 0x9e3779b1)
  h = Math.imul(h ^ (h >>> 16), 0x85ebca6b)
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35)
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296
}

/** 0 → 1: how far the altocumulus is there at `hours` (simulated, since midnight of day zero). */
export function altocumulusPresence(hours: number) {
  const position = hours / spellHours
  const spell = Math.floor(position)
  const moisture = lerp(draw(spell), draw(spell + 1), smoothstep(0, 1, position - spell))
  const hour = ((hours % 24) + 24) % 24
  const midday = Math.max(0, Math.cos(((hour - 13) / 12) * Math.PI))
  return smoothstep(forms, whole, moisture) * (1 - middayThinning * midday)
}
