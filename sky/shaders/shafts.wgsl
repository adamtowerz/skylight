// Light shafts (crepuscular rays): sunlight pouring through the gaps between the heaps and
// scattered toward the eye by the haze, in beams that fan out from the sun and converge again on
// the point opposite it.
//
// Aerosols scatter sunlight sharply forward (the Mie phase, g ≈ 0.8), and in air lit through a gap
// that forward peak is what the eye sees as a beam. The sky-view LUT holds the air's light as an
// average: blurred by its coarse texels and never broken by cloud. What it misses is the contrast
// between the sunlit and the shaded columns, and that is what is restored here, amplified per
// mood (`shaftStrength`). Each view ray is marched up to the cloud tops against the cloud shadow
// map (cloudshadow.wgsl), as in the volumetric shadowing of Hillaire 2016 (§5), for two things:
// the aerosols' single scattering of the key light as if all the air were lit, reddened by its
// path through the atmosphere, and the share of it that actually is. The scene adds that light
// times how far the share strays from its average around the ray (shaftmean.wgsl): lit lanes
// brighten, shaded ones darken, and the sky keeps its mean. Open sky, lit all the way, and night
// are left as they were, and the haze near the sun gains no veil.
//
// The view ray is marched in a few jittered, stratified steps; the shadows are soft and the
// integrand smooth, so what error is left sits well under the grain.

const SHAFT_STEPS = 32;
// Beams are a low light's: under a high sun the lanes stand upright, short across the view, and
// the light crosses little haze to reach them. Full below the first sine of the light's
// elevation (≈ 11.5°), gone above the second (30°).
const LOW_LIGHT = vec2f(0.2, 0.5);
// Beams are columns of haze, not the glare around the sun: within 5° of it the sky's own glow and
// aureole take over, and the beams' phase holds at its value there (the cosine).
const AUREOLE = 0.9962;

// Along view ray `dir`, up to the cloud tops: rgb = the beams' radiance if all the air were lit,
// a = the share of it that is. `jitter` in [0, 1) offsets the steps per pixel.
fn beams(dir: vec3f, jitter: f32) -> vec4f {
  let key = keyLight();
  let low = 1.0 - smoothstep(LOW_LIGHT.x, LOW_LIGHT.y, key.direction.y);
  if (low <= 0.0 || all(key.illuminance <= vec3f(0.0))) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let frame = cloudShadowFrame(key.direction, vec2f(textureDimensions(cloudShadowMap)));
  let mie = miePhase(min(dot(dir, key.direction), AUREOLE));
  let r = observerRadius();
  let eye = vec3f(0.0, r, 0.0);
  let dt = raySphere(r, dir.y, u.bottomRadius + u.cloudTop).y / f32(SHAFT_STEPS);
  var throughput = vec3f(1.0);
  var scattered = vec3f(0.0);
  var lit = 0.0;
  for (var i = 0; i < SHAFT_STEPS; i++) {
    let p = eye + dir * (f32(i) + jitter) * dt;
    let m = medium(length(p) - u.bottomRadius);
    let stepTransmittance = exp(-m.extinction * dt);
    // Hillaire's energy-conserving step, as in the sky-view LUT.
    let step = throughput * m.mieScattering * transmittanceAt(p, key.direction)
      * (1.0 - stepTransmittance) / max(m.extinction, vec3f(1e-9));
    scattered += step;
    lit += luminance(step) * exp(-cloudShadowDepth(frame, p));
    throughput *= stepTransmittance;
  }
  let share = lit / max(luminance(scattered), 1e-12);
  return vec4f(u.shaftStrength * low * mie * key.illuminance * scattered, share);
}
