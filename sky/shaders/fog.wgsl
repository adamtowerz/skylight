// Radiation fog: a layer of droplets lying on the ground, the eye inside it near the bottom, so
// everything else (the air above, the clouds, the sun, moon and stars) is seen through it. The
// layer is thin and nearly uniform, and droplets far larger than light's wavelengths scatter all
// colours alike, so it needs no march: it is a plane-parallel slab of grey, conservative
// scatterers, solved in closed form per view ray.
//
// What lies beyond comes through dimmed by exp(−τ/μ): τ is the fog's optical depth above the eye,
// μ the view's zenith cosine, so thin fog still shows the blue straight up and hides it at a slant.
// The light it takes away is not lost but scattered, over and over, and comes out below as a
// diffuse glow. How much of the sunlight on the fog's top gets through, direct or diffuse, is the
// two-stream (Eddington) solution for a conservative slab (Shettle & Weinman 1970; Bohren 1987,
// "Multiple scattering of light and some of its observable consequences"). Where that diffuse
// light seems to come from broadens with every scattering: the droplets' forward phase (g ≈ 0.85)
// raised to the number of scatterings a ray has suffered, so a thin mist glows around the sun and
// a thick bank is an even, luminous white. The moon lights it the same way; the sky's own light
// comes in from the whole dome, and the grass below bounces some of it back up, so the fog mixes
// every colour of the sky into one milky light.
//
// The fog's top is ragged: its thickness breathes with low-frequency noise, carried slowly
// overhead by the breeze at the ground and churning more slowly still, so that thin fog opens
// into patches of blue and the veil is never flat. Everything is smooth in the view direction and
// in time, so nothing flickers.

// Mean cosine of scattering by fog droplets in visible light.
const FOG_ANISOTROPY = 0.85;
// Half of what a droplet takes out of a beam it only diffracts, into a cone a few degrees wide
// (the extinction paradox): the phase of light scattered by diffraction alone.
const DIFFRACTION = 0.96;
// Size of the fog top's wisps east–west and north–south, km: drawn out along the breeze, which
// blows from the west. And how far their thickness strays from the mean (±).
const WISP_SIZE = vec2f(0.3, 0.12);
const RAGGEDNESS = 0.55;
// The lowest zenith cosine the slab is seen through: a flat layer seen edge-on would need an
// infinite path through it.
const GRAZING = 0.05;
// Fog lies in banks a few kilometres across: a low light slants in through their ragged tops and
// sides, not only through a plane, so the slab is lit no more grazing than that allows.
const BANK_WIDTH = 3.0;
// The sky dome is gathered from the zenith and two rings of headings turned with the sun (so its
// glow is never missed or aliased), weighted by the irradiance each band sends onto the fog's top.
const DOME_RINGS = array(vec2f(0.259, 0.35), vec2f(0.766, 0.5)); // (sine of elevation, weight)
const DOME_ZENITH = 0.15;

// Optical depth of the fog straight above the eye where view ray `dir` leaves it.
fn fogDepthAbove(dir: vec3f) -> f32 {
  let leaves = dir.xz / max(dir.y, GRAZING) * u.fogDepth;
  let p = (leaves - u.fogWind) / WISP_SIZE;
  let noise = 0.65 * valueNoise(vec3f(p, u.fogChurn)) + 0.35 * valueNoise(vec3f(2.3 * p + 17.0, 1.6 * u.fogChurn));
  // Stretched so the wisps span their full range: thick ribbons and thin places between them.
  let wisps = smoothstep(0.2, 0.8, noise);
  return u.fogExtinction * u.fogDepth * (1.0 + RAGGEDNESS * (2.0 * wisps - 1.0));
}

// Eddington's reflectance of a conservative slab of optical depth `tau` lit from zenith cosine
// `mu`; whatever it does not reflect, it transmits, direct or diffuse.
fn fogReflectance(tau: f32, mu: f32) -> f32 {
  let diffusion = 0.75 * (1.0 - FOG_ANISOTROPY) * tau;
  return (diffusion + (0.5 - 0.75 * mu) * (1.0 - exp(-tau / mu))) / (1.0 + diffusion);
}

// Radiance of the light a light of illuminance `illuminance` (on the fog's top, from `light`)
// sends down through the fog toward the eye along `dir`, less what it lets through unscattered.
// `path` scales the diffuse part by how much fog the eye looks through (see `fogAlong`).
fn fogGlow(dir: vec3f, light: vec3f, illuminance: vec3f, tau: f32, path: f32) -> vec3f {
  let mu = max(light.y, u.fogDepth / BANK_WIDTH);
  let direct = exp(-tau / mu);
  let cosTheta = dot(dir, light);
  // Light only ever diffracted keeps close to the light's direction: its soft disc and aureole.
  let diffracted = exp(-0.5 * tau / mu) - direct;
  // The rest is diffuse, and each scattering blurs its forward peak further; its phase is
  // normalised over the lower hemisphere as it goes from the light's direction (g → 1) to
  // uniform (g → 0).
  let diffuse = max(1.0 - fogReflectance(tau, mu) - direct - diffracted, 0.0);
  let g = pow(FOG_ANISOTROPY, 1.0 + tau / mu);
  let hemisphere = 0.25 * (1.0 - g) + g * mu;
  return illuminance * (diffracted * henyeyGreenstein(cosTheta, DIFFRACTION)
    + path * mu * diffuse * henyeyGreenstein(cosTheta, g) / hemisphere);
}

// The sky's radiance on the fog's top, averaged over the whole dome as the irradiance it sends:
// deep blue zenith, bright horizon and the glow around the sun, mixed as the fog mixes them.
fn skyOnFog() -> vec3f {
  let toward = select(vec2f(1.0, 0.0), normalize(u.sunDirection.xz), dot(u.sunDirection.xz, u.sunDirection.xz) > 1e-8);
  var sum = DOME_ZENITH * skyViewRadiance(vec3f(0.0, 1.0, 0.0));
  for (var ring = 0; ring < 2; ring++) {
    let elevation = DOME_RINGS[ring];
    let across = sqrt(1.0 - elevation.x * elevation.x);
    for (var i = 0; i < 4; i++) {
      let heading = f32(i) * 0.5 * PI;
      let horizontal = cos(heading) * toward + sin(heading) * vec2f(-toward.y, toward.x);
      sum += 0.25 * elevation.y * skyViewRadiance(vec3f(across * horizontal.x, elevation.x, across * horizontal.y));
    }
  }
  return sum;
}

// Along view ray `dir`: rgb the light the fog scatters toward the eye, a the share of what lies
// beyond that it lets through.
fn fogAlong(dir: vec3f) -> vec4f {
  if (u.fogExtinction <= 0.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let tau = fogDepthAbove(dir);
  let mu = max(dir.y, GRAZING);
  let through = exp(-tau / mu);
  // Thin fog is brighter at a slant, where the eye looks through more of it; thick fog glows the
  // same from every direction. Normalised to the diffuse light's mean path (zenith cosine ½).
  let path = (1.0 - through) / max(1.0 - exp(-2.0 * tau), 1e-4);
  let r = observerRadius();
  let sun = u.sunIlluminance * transmittance(r, u.sunDirection.y);
  let moon = u.moonIlluminance * transmittance(r, u.moonDirection.y);
  let sky = path * skyOnFog() * max(1.0 - fogReflectance(tau, 0.5) - exp(-2.0 * tau), 0.0);
  let glow = fogGlow(dir, u.sunDirection, sun, tau, path) + fogGlow(dir, u.moonDirection, moon, tau, path) + sky;
  // What gets through lights the grass, and the fog sends part of its bounce back down again.
  let bounce = 1.0 / (1.0 - u.groundAlbedo * fogReflectance(tau, 0.5));
  return vec4f(glow * bounce, through);
}
