// The sky dome along a view ray: the air itself (sky-view LUT per light, plus airglow), and what
// lies beyond it (sun, moon, Milky Way) seen through the atmosphere's transmittance, which reddens
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

@group(0) @binding(10) var milkyWayMap: texture_2d<f32>; // equatorial, equirectangular
@group(0) @binding(11) var milkyWaySampler: sampler; // wraps around in right ascension

// Angular size of one scene pixel: disk edges are sized against it so they neither alias nor
// shimmer as the camera breathes.
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

// The Milky Way's radiance along view ray `dir`, from the map made once by `milkyway.wgsl`.
fn milkyWay(dir: vec3f) -> vec3f {
  let equatorial = toEquatorial(dir);
  let uv = vec2f(atan2(equatorial.y, equatorial.x) / TAU, 0.5 - asin(clamp(equatorial.z, -1.0, 1.0)) / PI);
  return textureSampleLevel(milkyWayMap, milkyWaySampler, uv, 0.0).rgb;
}

// The sky along a view ray: rgb its radiance, a how much of what lies beyond the moon shows
// through its disk. The stars are drawn later, at the display's own resolution, by `post`; the
// scene hands them this, times the clouds' transmittance, as each pixel's view to space.
fn skyRadiance(dir: vec3f) -> vec4f {
  let air = skyViewRadiance(dir);
  let throughAir = transmittance(observerRadius(), dir.y);
  let lunar = moon(dir);
  let beyond = sun(dir) + lunar.rgb + milkyWay(dir) * (1.0 - lunar.a);
  return vec4f(air + throughAir * beyond, 1.0 - lunar.a);
}
