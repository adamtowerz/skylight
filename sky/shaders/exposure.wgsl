// Auto-exposure on the GPU, so it never round-trips through the CPU. One workgroup looks at
// the sky through the camera's frustum (a 16 × 16 grid of sky-view LUT samples, seen through the
// deck and the fog, on average), takes the log-average luminance, and exposes for it with a compressed key: exposure ∝
// L^(−COMPRESSION) rather than L⁻¹, so night stays darker than day and a sunset keeps its glow
// instead of being normalised to grey. The result adapts smoothly over time, like an eye. Each
// invocation also looks once at the whole dome, cosine-weighted, and their mean is the light a
// raindrop shows (rain.wgsl): a drop is a tiny fisheye onto the sky above it.

@group(0) @binding(5) var<storage, read_write> exposure: Exposure;

const GRID = 16u;
const SAMPLES = GRID * GRID;
// Exposure at a log-average sky luminance of 1.
const KEY = 0.17;
// 1 would fully normalise brightness; 0 would be a fixed exposure.
const COMPRESSION = 0.68;
// Adaptation rate, per second.
const ADAPTATION = 1.5;
// Fog, like snow, is a high-key scene that a meter would render grey: as a photographer exposing
// for it would, open up by as many stops as it (or an overcast deck) veils the view.
const HIGH_KEY = 0.8;

// Per sample: log2 of its luminance and how far fog or the deck veils it; and the dome's radiance.
var<workgroup> metered: array<vec2f, SAMPLES>;
var<workgroup> dome: array<vec3f, SAMPLES>;

// The sky along `dir` as the eye sees it: through the fog it lies in and the deck on average.
fn seen(dir: vec3f, onFog: vec3f) -> vec4f {
  let fog = fogAlong(dir);
  let sky = overcast(dir, skyViewRadiance(dir), onFog);
  return vec4f(fog.rgb + fog.a * sky.rgb, fog.a * sky.a);
}

// The grid cell `cell` of GRID × GRID mapped onto the upper hemisphere with cosine-weighted density
// (Malley's method: uniform over the disc, lifted onto the dome).
fn domeDirection(cell: vec2u) -> vec3f {
  let square = (vec2f(cell) + 0.5) / f32(GRID);
  let across = sqrt(square.x);
  let heading = TAU * square.y;
  return vec3f(across * cos(heading), sqrt(1.0 - square.x), across * sin(heading));
}

@compute @workgroup_size(GRID, GRID)
fn main(@builtin(local_invocation_id) id: vec3u, @builtin(local_invocation_index) index: u32) {
  let ndc = (vec2f(id.xy) + 0.5) / f32(GRID) * 2.0 - 1.0;
  let ray = u.cameraForward + ndc.x * u.tanHalfFov.x * u.cameraRight + ndc.y * u.tanHalfFov.y * u.cameraUp;
  let onFog = skyOnFog();
  let view = seen(normalize(ray), onFog);
  metered[index] = vec2f(log2(max(luminance(view.rgb), 1e-8)), 1.0 - view.a);
  dome[index] = seen(domeDirection(id.xy), onFog).rgb;

  for (var stride = SAMPLES / 2u; stride > 0u; stride >>= 1u) {
    workgroupBarrier();
    if (index < stride) {
      metered[index] += metered[index + stride];
      dome[index] += dome[index + stride];
    }
  }
  if (index == 0u) {
    let average = metered[0] / f32(SAMPLES);
    let desired = log2(KEY) - COMPRESSION * average.x + HIGH_KEY * average.y;
    // The buffer starts zeroed: take the first frame's exposure as is.
    let previous = exposure.value;
    let adapted = select(desired, mix(log2(previous), desired, 1.0 - exp(-ADAPTATION * u.dt)), previous > 0.0);
    exposure.value = exp2(adapted);
    exposure.dome = dome[0] / f32(SAMPLES);
  }
}
