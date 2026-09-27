// The sky dome along a view ray: the air itself (sky-view LUT per light, plus airglow), and what
// lies beyond it (sun, moon, stars) seen through the atmosphere's transmittance, which reddens
// them near the horizon and hides them below it.

const SUN_ANGULAR_RADIUS = 0.0061; // ≈ 0.35°, slightly amplified
// Disk radiance per unit illuminance. Physically 1/Ω ≈ 8500 at this size; far less keeps it in
// half-float range and lets a low sun read as a coloured ball rather than a white hole.
const SUN_DISK_RADIANCE = 60.0;
// Aureole: the forward-scattering peak narrower than a sky-view texel, and a touch of eye glare.
const SUN_AUREOLE = 0.08;
const SUN_AUREOLE_WIDTH = 0.01; // radians

const MOON_ANGULAR_RADIUS = 0.011; // ≈ 0.63°, amplified
// Radiance of the full moon's disk: silvery, and far dimmer than reality relative to the sun,
// because the night sky here is amplified much more than the moon; its phase and maria survive.
const MOON_RADIANCE = vec3f(0.14, 0.15, 0.165);
// Earthshine: the night side is faintly lit by the day-lit Earth.
const EARTHSHINE = 0.004;
// A tight silvery glow; the wider aureole comes from the moonlit sky-view layer.
const MOON_HALO = 0.03;
const MOON_HALO_WIDTH = 0.03; // radians

// Stars live in cells of a 3D grid in celestial coordinates, at most one per cell, kept only
// if it lands inside the cell's central region (see `stars`).
const STAR_CELLS = 80.0;
const STAR_MARGIN = 0.25;
// Flux of the faintest star; the rest follow N(>F) ∝ F^(−1.5), up to STAR_RANGE × brighter.
const STAR_FLUX = 1e-8;
const STAR_RANGE = 400.0;
const TWINKLE = 0.35;

// Angular size of one scene pixel: stars and disk edges are sized against it so they neither
// alias nor shimmer as the camera breathes.
fn pixelAngle() -> f32 {
  return 2.0 * u.tanHalfFov.y / u.resolution.y;
}

// Angle between two unit vectors, accurate for the tiny angles across a disk.
fn angleBetween(a: vec3f, b: vec3f) -> f32 {
  return atan2(length(cross(a, b)), dot(a, b));
}

// Anti-aliased coverage of a disk of angular radius `radius` at angle `angle` from its centre.
fn diskCoverage(angle: f32, radius: f32) -> f32 {
  return saturate((radius - angle) / pixelAngle() + 0.5);
}

// Sun disk with wavelength-dependent power-law limb darkening (redder, dimmer at the limb), and
// its aureole.
fn sun(dir: vec3f) -> vec3f {
  let angle = angleBetween(dir, u.sunDirection);
  let x = min(angle / SUN_ANGULAR_RADIUS, 1.0);
  let limb = pow(vec3f(max(sqrt(1.0 - x * x), 1e-4)), vec3f(0.4, 0.5, 0.65));
  let disk = SUN_DISK_RADIANCE * limb * diskCoverage(angle, SUN_ANGULAR_RADIUS);
  let aureole = SUN_AUREOLE * exp(-angle / SUN_AUREOLE_WIDTH);
  return u.sunIlluminance * (disk + aureole);
}

fn valueNoise(p: vec3f) -> f32 {
  let cell = bitcast<vec3u>(vec3i(floor(p)));
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let x00 = mix(hash3(cell), hash3(cell + vec3u(1u, 0u, 0u)), w.x);
  let x10 = mix(hash3(cell + vec3u(0u, 1u, 0u)), hash3(cell + vec3u(1u, 1u, 0u)), w.x);
  let x01 = mix(hash3(cell + vec3u(0u, 0u, 1u)), hash3(cell + vec3u(1u, 0u, 1u)), w.x);
  let x11 = mix(hash3(cell + vec3u(0u, 1u, 1u)), hash3(cell + vec3u(1u, 1u, 1u)), w.x);
  return mix(mix(x00, x10, w.y), mix(x01, x11, w.y), w.z);
}

// Maria: darker basalt plains, from noise over the moon's surface in a frame fixed to the moon
// (it always shows us the same face, oriented by the celestial pole).
fn maria(normal: vec3f) -> f32 {
  let toward = -u.moonDirection;
  let east = normalize(cross(u.skyRotation[2].xyz, toward));
  let local = vec3f(dot(normal, east), dot(normal, cross(toward, east)), dot(normal, toward));
  let plains = 0.65 * valueNoise(local * 2.5 + 3.0) + 0.35 * valueNoise(local * 6.0);
  return mix(1.0, 0.55, smoothstep(0.42, 0.66, plains));
}

// The moon: a sphere lit by the real sun direction, so its phase is always right. Lommel–Seeliger
// reflectance gives regolith's flat, limb-bright look; a faint silvery halo surrounds it.
// rgb = radiance, a = coverage (it hides the stars behind it).
fn moon(dir: vec3f) -> vec4f {
  let angle = angleBetween(dir, u.moonDirection);
  let coverage = diskCoverage(angle, MOON_ANGULAR_RADIUS);
  let halo = MOON_HALO * u.moonIlluminance * exp(-angle / MOON_HALO_WIDTH);
  if (coverage <= 0.0) {
    return vec4f(halo, 0.0);
  }
  let offset = (dir - u.moonDirection * dot(dir, u.moonDirection)) / sin(MOON_ANGULAR_RADIUS);
  let facing = sqrt(max(0.0, 1.0 - dot(offset, offset)));
  let normal = offset - u.moonDirection * facing;
  let incidence = max(dot(normal, u.sunDirection), 0.0);
  let reflectance = 2.0 * incidence / max(incidence + facing, 1e-4) + EARTHSHINE;
  let surface = MOON_RADIANCE * maria(normal) * reflectance;
  return vec4f(surface * coverage + halo, coverage);
}

// Stars: at most one per cell of a 3D grid in celestial coordinates (they turn with the Earth).
// A star is kept only if it lands well inside its own cell, so no neighbour ever needs checking.
// Each is a Gaussian at least a pixel wide carrying a fixed flux, so it never aliases; bright
// stars spread a little wider, as they do on film.
fn stars(dir: vec3f) -> vec3f {
  let rotation = mat3x3f(u.skyRotation[0].xyz, u.skyRotation[1].xyz, u.skyRotation[2].xyz);
  let celestial = transpose(rotation) * dir;
  let cellCorner = floor(celestial * STAR_CELLS);
  let cell = bitcast<vec3u>(vec3i(cellCorner));
  // Independent random numbers per cell: offsets along z by a prime far beyond the grid.
  let stream = vec3u(0u, 0u, 7919u);
  let jitter = vec3f(hash3(cell), hash3(cell + stream), hash3(cell + 2u * stream));
  let star = normalize(cellCorner + jitter);
  let inCell = star * STAR_CELLS - cellCorner;
  if (any(inCell < vec3f(STAR_MARGIN)) || any(inCell > vec3f(1.0 - STAR_MARGIN))) {
    return vec3f(0.0);
  }

  let brightness = min(pow(hash3(cell + 3u * stream) + 1e-6, -1.0 / 1.5), STAR_RANGE);
  let warmth = hash3(cell + 4u * stream);
  let color = mix(vec3f(0.78, 0.87, 1.18), vec3f(1.12, 0.94, 0.78), warmth * warmth * warmth);
  // Scintillation grows with the air mass the starlight crosses.
  let phase = hash3(cell + 5u * stream) * TAU;
  let scintillation = TWINKLE * min(1.0 / max(dir.y, 0.05), 3.0) / 3.0;
  let twinkle = 1.0 + scintillation * sin(u.time * (5.0 + 4.0 * warmth) + phase) * sin(u.time * 1.7 + 2.0 * phase);

  let sigma = 0.55 * pixelAngle() * min(pow(brightness, 0.15), 2.0);
  let angle = angleBetween(celestial, star);
  let spread = exp(-0.5 * angle * angle / (sigma * sigma)) / (TAU * sigma * sigma);
  return color * STAR_FLUX * brightness * twinkle * spread;
}

fn skyRadiance(dir: vec3f) -> vec3f {
  let throughAir = transmittance(observerRadius(), dir.y);
  let lunar = moon(dir);
  let beyond = sun(dir) + lunar.rgb + stars(dir) * (1.0 - lunar.a);
  return skyViewRadiance(dir) + throughAir * beyond;
}
