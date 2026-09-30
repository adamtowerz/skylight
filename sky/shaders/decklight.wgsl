// How light comes down through the deck, a low layer of stratus or nimbostratus (deck.wgsl): too
// thick and too even to march, it is a slab of droplets solved in closed form (slab.wgsl). The
// key light and the sky's whole dome light its top; what the eye sees from below is what diffuses
// through, so the grey underside is luminous rather than dark, brighter where the deck is thinner,
// and brightest toward the sun where it is thin enough to still show which way the light comes
// from. Seen from beneath, the light leaving a thick slab is not uniform but limb-darkened, like
// light escaping a star: the overcast sky is about three times brighter overhead than at the
// horizon (the escape function 3(1 + 2μ)/7, Chandrasekhar 1960; the CIE standard overcast sky,
// Moon & Spencer 1942). The grass bounces some of what gets through back up, and the deck sends
// part of that down again. The same light, without the deck's texture, is what the exposure
// meters and what the rain beneath it scatters.

// Height of the deck's top above its base, km: where the key light reaches it through the
// atmosphere, so it keeps the sun for a moment after the ground has lost it.
const DECK_THICKNESS = 1.5;
// A deck's top is lumpy, so a low light is taken in no more grazing than this (a zenith cosine).
const DECK_GRAZING = 0.1;
// The lowest zenith cosine the deck is seen through.
const DECK_VIEW_GRAZING = 0.05;
// The deck's mean column, as a share of its thickest, where it is whole (deck.wgsl's shape).
const DECK_MEAN_COLUMN = 0.85;

// Where view ray `dir` meets the sphere `height` km above the ground (planet-centred), and how far.
fn onLayer(dir: vec3f, height: f32) -> vec4f {
  let r = observerRadius();
  let t = raySphere(r, dir.y, u.bottomRadius + height).y;
  return vec4f(vec3f(0.0, r, 0.0) + dir * t, t);
}

// The light the deck sends down along `dir` from its base at `base` (planet-centred), where its
// column has optical depth `tau`, lit by the key light and by `sky`, the dome's radiance on
// average. rgb: its radiance; a: the share of what lies beyond that it scatters only a little
// forward, so that it still shows, blurred, as through a thin veil it does: skylight keeps its
// way as far as the key light's does (slab.wgsl).
fn deckGlow(dir: vec3f, base: vec3f, tau: f32, sky: vec3f) -> vec4f {
  let key = keyLight();
  let top = base * (1.0 + DECK_THICKNESS / length(base));
  let illuminance = key.illuminance * transmittanceAt(top, key.direction);
  let escape = 3.0 * (1.0 + 2.0 * max(dir.y, 0.0)) / 7.0;
  let lit = slabGlow(dir, key.direction, max(key.direction.y, DECK_GRAZING), illuminance, tau, escape);
  let diffuse = max(1.0 - slabReflectance(tau, 0.5) - exp(-2.0 * tau), 0.0);
  let forward = pow(DROPLET_ANISOTROPY, 1.0 + 2.0 * tau) * diffuse;
  let bounce = 1.0 / (1.0 - u.groundAlbedo * slabReflectance(tau, 0.5));
  return vec4f((lit + escape * sky * (diffuse - forward)) * bounce, forward);
}

// The view along `dir` of `behind` (the sky and clouds beyond) through the deck on average,
// without its texture (its mean column over the share of the sky it covers): rgb the radiance, a
// the share of `behind` that shows.
fn overcast(dir: vec3f, behind: vec3f, sky: vec3f) -> vec4f {
  if (u.deckCover <= 0.0) {
    return vec4f(behind, 1.0);
  }
  let tau = DECK_MEAN_COLUMN * u.deckDepth;
  let glow = deckGlow(dir, onLayer(dir, u.deckBase).xyz, tau, sky);
  let through = mix(1.0, exp(-tau / max(dir.y, DECK_VIEW_GRAZING)) + glow.a, u.deckCover);
  return vec4f(u.deckCover * glow.rgb + through * behind, through);
}
