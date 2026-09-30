// The atmosphere, after Hillaire 2020 ("A Scalable and Production Ready Sky and Atmosphere
// Rendering Technique", EGSR), using Bruneton & Neyret 2008's (r, μ) ray parametrisation:
// r is the distance from the planet centre (km), μ the cosine of a ray's zenith angle there.
//
// Three LUTs are rebuilt every frame (moods change the air): transmittance to space,
// multiscattering transfer ψ_ms, and the sky-view radiance around the observer. This module holds
// the shared physics and the lookups. For other modules, the API is:
//
//   transmittance(r, mu)      light from space reaching radius r from direction μ; 0 below the
//                             horizon, softened over ±0.3° (the sun's disk, a gentle Earth shadow)
//   transmittanceAt(p, dir)   the same for a position p (km, planet-centred) and a direction
//   raySphere(r, mu, radius)  where a ray enters and leaves a shell (clouds, atmosphere)
//   skyViewRadiance(dir)      atmosphere-only radiance seen from the observer: sunlit + moonlit
//                             air + airglow. The sky behind everything, and ambient for clouds.
//   aerialPerspective(radiance, dir, distance)
//                             dims and veils something `distance` km along a view ray
//
// Bindings 1–4 are the LUT inputs; a pass binds only those its entry point reads.

@group(0) @binding(1) var transmittanceLut: texture_2d<f32>;
@group(0) @binding(2) var multiscatteringLut: texture_2d<f32>;
@group(0) @binding(3) var skyViewLut: texture_2d_array<f32>;
@group(0) @binding(4) var lutSampler: sampler;

// Sky-view LUT layers: the sky lit by each light, per unit of its illuminance.
const SUN_LAYER = 0u;
const MOON_LAYER = 1u;

// sin(0.3°): half-width of the soft band over which the planet eclipses a light at the horizon.
const HORIZON_SOFTNESS = 0.00524;

// Optical properties of the air at one altitude, in km⁻¹.
struct Medium {
  rayleighScattering: vec3f,
  mieScattering: vec3f,
  extinction: vec3f,
}

// Rayleigh and Mie densities fall off exponentially with altitude; ozone is a tent around
// `ozoneCenter` that only absorbs (its Chappuis band is what turns twilight violet).
fn medium(altitude: f32) -> Medium {
  let h = max(altitude, 0.0);
  let rayleigh = exp(-h / u.rayleighScaleHeight);
  let mie = exp(-h / u.mieScaleHeight);
  let ozone = max(0.0, 1.0 - abs(h - u.ozoneCenter) / (0.5 * u.ozoneWidth));
  let rayleighScattering = u.rayleighScattering * rayleigh;
  let mieScattering = u.mieScattering * mie;
  let absorption = u.mieAbsorption * mie + u.ozoneAbsorption * ozone;
  return Medium(rayleighScattering, mieScattering, rayleighScattering + mieScattering + absorption);
}

fn rayleighPhase(cosTheta: f32) -> f32 {
  return 3.0 / (16.0 * PI) * (1.0 + cosTheta * cosTheta);
}

// Henyey–Greenstein 1941: the phase function of a medium scattering with mean cosine g.
fn henyeyGreenstein(cosTheta: f32, g: f32) -> f32 {
  let g2 = g * g;
  return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

// Cornette & Shanks 1992: Henyey–Greenstein with a (1 + cos²θ) factor, which keeps strongly
// forward-scattering aerosols' back-scatter plausible.
fn miePhase(cosTheta: f32) -> f32 {
  let g = u.mieAnisotropy;
  let g2 = g * g;
  let k = 3.0 / (8.0 * PI) * (1.0 - g2) / (2.0 + g2);
  return k * (1.0 + cosTheta * cosTheta) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
}

fn observerRadius() -> f32 {
  return u.bottomRadius + u.observerAltitude;
}

// Distances along a ray (from radius r, zenith cosine mu) to where it enters and leaves a sphere
// about the planet centre. From inside, x < 0 < y. Both are negative when the ray misses.
fn raySphere(r: f32, mu: f32, radius: f32) -> vec2f {
  let discriminant = r * r * (mu * mu - 1.0) + radius * radius;
  if (discriminant < 0.0) {
    return vec2f(-1.0);
  }
  let s = sqrt(discriminant);
  return vec2f(-r * mu - s, -r * mu + s);
}

fn hitsGround(r: f32, mu: f32) -> bool {
  return raySphere(r, mu, u.bottomRadius).x > 0.0;
}

// Zenith cosine of the geometric horizon seen from radius r.
fn horizonMu(r: f32) -> f32 {
  let s = u.bottomRadius / r;
  return -sqrt(max(0.0, 1.0 - s * s));
}

// Radius reached a distance t along a ray from radius r with zenith cosine mu.
fn radiusAlong(r: f32, mu: f32, t: f32) -> f32 {
  return sqrt(t * t + 2.0 * r * mu * t + r * r);
}

// Zenith cosine, at that point (radius rt), of a direction whose zenith cosine at the ray's
// origin is `muDirection` and whose cosine with the ray is `nu` (1 for the ray itself).
fn muAlong(r: f32, muDirection: f32, nu: f32, t: f32, rt: f32) -> f32 {
  return clamp((r * muDirection + t * nu) / rt, -1.0, 1.0);
}

// Texel centres span [0, 1] exactly, so a LUT's edge texels hold its parametrisation's ends.
fn unitToTexel(unit: vec2f, size: vec2u) -> vec2f {
  let s = vec2f(size);
  return (saturate(unit) * (s - 1.0) + 0.5) / s;
}

fn texelToUnit(texel: vec2u, size: vec2u) -> vec2f {
  return vec2f(texel) / (vec2f(size) - 1.0);
}

// Transmittance LUT (Bruneton 2017): u maps the distance d to the top of the atmosphere between
// its extremes (straight up … grazing the horizon), v the radius via ρ = √(r² − bottom²), the
// distance from radius r to its horizon (`horizon` is ρ at the top). Rays that hit the ground
// clamp to the horizon texel.
fn transmittanceUnit(r: f32, mu: f32) -> vec2f {
  let horizon = sqrt(u.topRadius * u.topRadius - u.bottomRadius * u.bottomRadius);
  let rho = sqrt(max(0.0, r * r - u.bottomRadius * u.bottomRadius));
  let d = max(0.0, raySphere(r, mu, u.topRadius).y);
  let dMin = u.topRadius - r;
  let dMax = rho + horizon;
  return vec2f((d - dMin) / (dMax - dMin), rho / horizon);
}

// Inverse of `transmittanceUnit`: (r, mu) for a LUT coordinate.
fn transmittanceRay(unit: vec2f) -> vec2f {
  let horizon = sqrt(u.topRadius * u.topRadius - u.bottomRadius * u.bottomRadius);
  let rho = horizon * unit.y;
  let r = sqrt(rho * rho + u.bottomRadius * u.bottomRadius);
  let dMin = u.topRadius - r;
  let d = mix(dMin, rho + horizon, unit.x);
  let mu = select((horizon * horizon - rho * rho - d * d) / (2.0 * r * d), 1.0, d == 0.0);
  return vec2f(r, clamp(mu, -1.0, 1.0));
}

// Transmittance from radius r to space along mu, ignoring the planet.
fn transmittanceToSpace(r: f32, mu: f32) -> vec3f {
  let unit = transmittanceUnit(clamp(r, u.bottomRadius, u.topRadius), mu);
  return textureSampleLevel(transmittanceLut, lutSampler, unitToTexel(unit, textureDimensions(transmittanceLut)), 0.0).rgb;
}

// How much of a light at zenith cosine mu clears the planet: a soft ±0.3° eclipse at the horizon.
fn horizonVisibility(r: f32, mu: f32) -> f32 {
  return smoothstep(-HORIZON_SOFTNESS, HORIZON_SOFTNESS, mu - horizonMu(r));
}

fn transmittance(r: f32, mu: f32) -> vec3f {
  return transmittanceToSpace(r, mu) * horizonVisibility(r, mu);
}

fn transmittanceAt(position: vec3f, dir: vec3f) -> vec3f {
  let r = length(position);
  return transmittance(r, dot(position, dir) / r);
}

// Multiscattering LUT (Hillaire 2020): ψ_ms per unit illuminance, by the light's zenith
// cosine (u) and altitude (v). Scaled by the local scattering coefficient, it stands in for
// every bounce past the first.
fn multiscattering(r: f32, muLight: f32) -> vec3f {
  let unit = vec2f(muLight * 0.5 + 0.5, (r - u.bottomRadius) / (u.topRadius - u.bottomRadius));
  return textureSampleLevel(multiscatteringLut, lutSampler, unitToTexel(unit, textureDimensions(multiscatteringLut)), 0.0).rgb;
}

// Sky-view LUT coordinates of a view direction relative to a light: u = azimuth from the light
// over [0, π] (the sky is mirror-symmetric about the light's vertical plane), v = √(elevation /
// (π/2)), dense near the horizon where colour changes fastest. The view never looks below it.
fn skyViewUnit(dir: vec3f, light: vec3f) -> vec2f {
  let view = dir.xz * inverseSqrt(max(dot(dir.xz, dir.xz), 1e-12));
  let toward = light.xz * inverseSqrt(max(dot(light.xz, light.xz), 1e-12));
  let azimuth = acos(clamp(dot(view, toward), -1.0, 1.0));
  let elevation = asin(saturate(dir.y));
  return vec2f(azimuth / PI, sqrt(elevation / (0.5 * PI)));
}

fn skyViewLayer(dir: vec3f, light: vec3f, layer: u32) -> vec3f {
  let texel = unitToTexel(skyViewUnit(dir, light), textureDimensions(skyViewLut));
  return textureSampleLevel(skyViewLut, lutSampler, texel, layer, 0.0).rgb;
}

// Airglow is emission, not scattering: a faint floor that keeps the night sky deep blue.
fn skyViewRadiance(dir: vec3f) -> vec3f {
  return skyViewLayer(dir, u.sunDirection, SUN_LAYER) * u.sunIlluminance
    + skyViewLayer(dir, u.moonDirection, MOON_LAYER) * u.moonIlluminance
    + u.nightGlow;
}

// Aerial perspective for a point `distance` km along view ray `dir` (e.g. a cloud). The air in
// between dims it by the transmittance between the two points (a ratio of LUT lookups, exact for
// rays that miss the ground) and veils it with the sky behind, in proportion.
fn aerialPerspective(radiance: vec3f, dir: vec3f, distance: f32) -> vec3f {
  let r = observerRadius();
  let rd = radiusAlong(r, dir.y, distance);
  let muD = muAlong(r, dir.y, 1.0, distance, rd);
  let behind = max(transmittanceToSpace(rd, muD), vec3f(1e-6));
  let between = min(transmittanceToSpace(r, dir.y) / behind, vec3f(1.0));
  return radiance * between + skyViewRadiance(dir) * (1.0 - between);
}
