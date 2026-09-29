// Cloud shadows: the cumulus as the key light sees it, kept in a Beer shadow map (Hillaire 2016,
// "Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite", §5; the volumetric cloud
// shadow map of Unreal's sky). The map is an orthographic view along the key light over the cloud
// layer and the air beneath it, out to SHADOW_RADIUS around the observer. Every texel is a line
// toward the light, and holds where along it the cumulus begins as seen from the light (the
// front), the mean extinction behind that, and the optical depth of all of it, so that from any
// point on the line the cloud between it and the light has optical depth
//
//   min(mean extinction × distance behind the front, whole optical depth):
//
// exact through one heap, and close through several, since behind the first it is dark either way.
// Front and extinction are stored premultiplied by the optical depth, so that where a lookup
// blends cloudy texels with clear ones, it blends only the cloudy ones' fronts.
//
// The map lives in cloud space, over the region around the observer, and turns with the light
// about the region's middle. Its window glides smoothly over the drifting field and the texels
// are filtered, so shadows travel with the clouds and the slow sun and never jump: snapping the
// window to whole texels, laid out from the planet's centre, made every turn of the light a
// jolt of up to half a texel, which a grazing sun stretches into a whole lane. Its height follows
// the light: seen along a grazing sun the whole
// region is a thin band, and the map spends every texel on it.
//
// Read at binding 8, through the atmosphere's bilinear, clamped sampler.

@group(0) @binding(8) var cloudShadowMap: texture_2d<f32>;

// Half-width of the region the map covers, km: every cloud and every stretch of air in view.
const SHADOW_RADIUS = 24.0;
// Share of the map's width, at either side, over which its shadows fade out.
const SHADOW_EDGE = 0.1;

// Where the map lies. Positions on it are cloud-space (x, y, s) about the region's middle: across
// the light horizontally, across it in its vertical plane, and along it toward the light.
struct ShadowFrame {
  x: vec3f,
  y: vec3f,
  toward: vec3f,
  window: vec2f, // half-size across x and y, km
  middle: vec3f, // cloud space
}

// The wind's offset, planet-centred km: world = cloud space + drift.
fn drift() -> vec3f {
  return vec3f(u.cloudWind.x, 0.0, u.cloudWind.y);
}

fn cloudShadowFrame(light: vec3f) -> ShadowFrame {
  let horizontal = length(light.xz);
  let x = select(vec3f(1.0, 0.0, 0.0), vec3f(-light.z, 0.0, light.x) / horizontal, horizontal > 1e-4);
  let y = cross(x, light);
  // The region runs from the ground to the cloud tops; seen along the light, its height is
  // foreshortened and its depth across the ground shows instead.
  let halfHeight = 0.5 * u.cloudTop;
  let window = vec2f(SHADOW_RADIUS, SHADOW_RADIUS * abs(light.y) + halfHeight * horizontal);
  let middle = vec3f(0.0, u.bottomRadius + halfHeight, 0.0) - drift();
  return ShadowFrame(x, y, light, window, middle);
}

// A cloud-space position's (x, y) as a uv over the map.
fn shadowUv(frame: ShadowFrame, position: vec3f) -> vec2f {
  let offset = position - frame.middle;
  return 0.5 + 0.5 * vec2f(dot(offset, frame.x), dot(offset, frame.y)) / frame.window;
}

// The point of a texel's line at s = 0 (planet-centred km, where the wind has carried it).
fn shadowLine(frame: ShadowFrame, uv: vec2f) -> vec3f {
  let offset = (2.0 * uv - 1.0) * frame.window;
  return frame.middle + offset.x * frame.x + offset.y * frame.y + drift();
}

// Optical depth of the cumulus between `p` (planet-centred km) and the key light.
fn cloudShadowDepth(frame: ShadowFrame, p: vec3f) -> f32 {
  let position = p - drift();
  let uv = shadowUv(frame, position);
  let fade = saturate((1.0 - abs(2.0 * uv.x - 1.0)) / SHADOW_EDGE);
  if (fade <= 0.0) {
    return 0.0;
  }
  let texel = textureSampleLevel(cloudShadowMap, lutSampler, uv, 0.0);
  let depth = texel.z;
  if (depth <= 0.0) {
    return 0.0;
  }
  let behind = texel.x / depth - dot(position - frame.middle, frame.toward);
  return min(texel.y / depth * max(behind, 0.0), depth) * fade;
}
