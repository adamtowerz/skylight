// Clouds along a view ray: a low grey deck when the weather brings one (deck.wgsl), then a
// raymarched cumulus shell (cumulus.wgsl) in front of a thin layer of
// altocumulus (altocumulus.wgsl) and a thin cirrus sheet (cirrus.wgsl), after Schneider 2015 ("The Real-time Volumetric Cloudscapes of Horizon
// Zero Dawn") and Hillaire 2016 ("Physically Based Sky, Atmosphere and Cloud Rendering in
// Frostbite"). This module holds what both layers share: the noise volume, the light they are
// lit by, the phase function, and the air between them and the eye.
//
// Positions are planet-centred km, as in the atmosphere. The key light reaching a cloud is its
// illuminance above the atmosphere times `transmittanceAt(p, light)`: clouds above the observer's
// horizon keep catching the sun, reddened by its long path, after it has set at the ground.

@group(0) @binding(5) var cloudNoise: texture_3d<f32>;
@group(0) @binding(6) var noiseSampler: sampler;

// Fraction of the ground below a cloud base that lies outside that cloud's own shadow.
const OWN_SHADOW = 0.5;

// The light shaping the clouds, and the ambient light around them.
struct CloudLighting {
  keyDirection: vec3f,
  keyIlluminance: vec3f, // above the atmosphere
  sky: vec3f, // ambient radiance from above
  shadedSky: vec3f, // the part of it seen by faces turned from the key light
  ground: vec3f, // ambient radiance from below, bounced off the grass
}

fn remap(x: f32, low: f32, high: f32, newLow: f32, newHigh: f32) -> f32 {
  return newLow + (x - low) / (high - low) * (newHigh - newLow);
}

fn sampleNoise(p: vec3f) -> vec4f {
  return textureSampleLevel(cloudNoise, noiseSampler, p, 0.0);
}

// A smooth displacement field (km) with features about a quarter of `tile` apart.
fn bend(position: vec2f, tile: f32, slice: f32) -> vec2f {
  let a = sampleNoise(vec3f(position / tile, slice)).r;
  let b = sampleNoise(vec3f(position / tile + 0.5, slice + 0.37)).r;
  return vec2f(a, b) - 0.5;
}

// The sky at 30° elevation, at horizontal heading `heading` (unit, xz).
fn skyRing(heading: vec2f) -> vec3f {
  return skyViewRadiance(vec3f(0.866 * heading.x, 0.5, 0.866 * heading.y));
}

// The sky's radiance averaged over the upper hemisphere (zenith plus a ring at 30° elevation),
// and over the half turned away from `light`. A cloud's shaded side sees only that half: the deep
// blue away from the sun rather than the white glow around it, which is why daylight shadows on
// clouds are blue (and violet at dusk).
fn skylight(light: vec3f) -> array<vec3f, 2> {
  let toward = select(vec2f(1.0, 0.0), normalize(light.xz), dot(light.xz, light.xz) > 1e-8);
  let side = vec2f(-toward.y, toward.x);
  let zenith = skyViewRadiance(vec3f(0.0, 1.0, 0.0));
  let turnedAway = zenith + skyRing(-toward) + skyRing(side) + skyRing(-side);
  return array(0.2 * (turnedAway + skyRing(toward)), 0.25 * turnedAway);
}

// Light bounced up from the grass (Lambertian): the sun and moon on it, plus the sky. Direct
// light only reaches the ground between the clouds, and about half of what a cloud base sees
// below it is its own shadow.
fn groundAmbient(sky: vec3f) -> vec3f {
  let r = observerRadius();
  let sunlit = u.sunIlluminance * transmittance(r, u.sunDirection.y) * max(u.sunDirection.y, 0.0)
    + u.moonIlluminance * transmittance(r, u.moonDirection.y) * max(u.moonDirection.y, 0.0);
  let irradiance = sunlit * OWN_SHADOW * (1.0 - u.cloudCoverage) + PI * sky;
  return u.groundAlbedo / PI * irradiance;
}

fn cloudLighting() -> CloudLighting {
  let key = keyLight();
  let sunSky = skylight(u.sunDirection);
  if (u.sunDirection.y > SUN_REACH) {
    return CloudLighting(key.direction, key.illuminance, sunSky[0], sunSky[1], groundAmbient(sunSky[0]));
  }
  // The shaded side turns from the sun to the moon as moonlight takes over, never all at once.
  let moonSky = skylight(u.moonDirection);
  let sky = mix(sunSky[0], moonSky[0], moonlight());
  let shadedSky = mix(sunSky[1], moonSky[1], moonlight());
  return CloudLighting(key.direction, key.illuminance, sky, shadedSky, groundAmbient(sky));
}

// The air between the eye and a cloud layer `distance` km away dims it and veils it with the sky
// behind, in proportion to the layer's opacity (rgb = radiance, a = transmittance).
fn throughAir(layer: vec4f, dir: vec3f, distance: f32) -> vec4f {
  let opacity = 1.0 - layer.a;
  if (opacity < 1e-4) {
    return layer;
  }
  return vec4f(aerialPerspective(layer.rgb / opacity, dir, distance) * opacity, layer.a);
}

// rgb: radiance scattered toward the eye; a: transmittance of whatever lies behind. `jitter` in
// [0, 1) offsets the raymarch per pixel, trading banding for fine noise that the grain hides.
// Nearest first: a whole deck hides everything, the heaps hide the altocumulus, and all of them
// hide the cirrus.
fn clouds(dir: vec3f, jitter: f32) -> vec4f {
  let lighting = cloudLighting();
  var layers = deck(dir, lighting);
  if (layers.a < OPAQUE) {
    return layers;
  }
  let heaps = cumulus(dir, jitter, lighting);
  layers = vec4f(layers.rgb + layers.a * heaps.rgb, layers.a * heaps.a);
  if (layers.a < OPAQUE) {
    return layers;
  }
  let middle = altocumulus(dir, jitter, lighting);
  layers = vec4f(layers.rgb + layers.a * middle.rgb, layers.a * middle.a);
  if (layers.a < OPAQUE) {
    return layers;
  }
  let high = cirrus(dir, lighting);
  return vec4f(layers.rgb + layers.a * high.rgb, layers.a * high.a);
}
