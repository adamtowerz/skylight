/**
 * The rain's drops, on the CPU: how large they are and how fast they fall at a rain rate (Marshall
 * & Palmer 1948; Atlas, Srivastava & Sekhon 1973), and how far they have come along their slant.
 * They fall through the air at their terminal speed and are carried with it, so in a wind they
 * come in along a slant at the speed of both together. `rain.wgsl` scrolls its lattices of drops
 * by that distance, so when a gust brings heavier rain, with larger, faster drops, or blows harder,
 * they speed up smoothly instead of the lattices jumping to a new pace.
 */

/** Marshall–Palmer: N(D) = N₀ e^(−ΛD), N₀ = 8000 m⁻³ mm⁻¹, Λ = 4.1 R^−0.21 mm⁻¹ (R in mm/h). */
const intercept = 8000
const slope = (rate: number) => 4.1 * rate ** -0.21

/** The median drop by volume, mm. */
const typicalDrop = (rate: number) => 3.67 / slope(rate)

/** Terminal fall speed of a drop `diameter` mm across, m/s. */
const fallSpeed = (diameter: number) => 9.65 - 10.3 * Math.exp(-0.6 * diameter)

/**
 * Drops larger than `smallest` mm landing per m² per second: N₀/Λ e^(−Λ D) of them per m³ (the
 * tail of the distribution), falling at about the typical drop's speed.
 */
export function dropsLanding(rate: number, smallest: number) {
  if (rate <= 0) return 0
  const lambda = slope(rate)
  return (intercept / lambda) * Math.exp(-lambda * smallest) * fallSpeed(typicalDrop(rate))
}

/**
 * The distance fallen is folded over this many metres: a whole number of every lattice's cells
 * (`rain.wgsl`: each layer's cells are 0.2, 0.3 and 0.4 m of fall), so the fold leaves no seam.
 */
const fold = 1200

export interface Rainfall {
  /** Advances the drops by `dt` seconds of rain at `rate` mm/h in a wind of `wind` m/s. */
  advance(dt: number, rate: number, wind: number): { rainFallen: number; rainFallSpeed: number }
}

export function trackRainfall(): Rainfall {
  let fallen = 0
  return {
    advance(dt, rate, wind) {
      const speed = fallSpeed(typicalDrop(Math.max(rate, 0.1)))
      fallen = (fallen + Math.hypot(speed, wind) * dt) % fold
      return { rainFallen: fallen, rainFallSpeed: speed }
    },
  }
}
