// The cloud noise volume, after Schneider 2015 ("The Real-time Volumetric Cloudscapes of Horizon
// Zero Dawn"): one tileable 128³ texture, generated once. R is Perlin–Worley, billowy Perlin fBm
// dilated by Worley cells, the cumulus shapes; G, B and A are Worley fBm at three rising
// frequencies, which erode those shapes and, sampled at a finer scale, carve their detail.
// Every octave's lattice wraps at the volume's edge, so the texture tiles along all three axes.

@group(0) @binding(0) var volume: texture_storage_3d<rgba8unorm, write>;

// Lattice cells across the volume for the lowest octave; each further octave doubles it.
const BASE_FREQUENCY = 4.0;
// fBm weights for three octaves (Schneider's), summing to 1.
const OCTAVE_WEIGHTS = vec3f(0.625, 0.25, 0.125);
// Where the raw sums mostly fall (≈ 2nd–98th percentile). Stretching them over [0, 1] spends
// all 8 bits on the range clouds use, and makes coverage thresholds behave linearly.
const PERLIN_WORLEY_RANGE = vec2f(0.5, 0.95);
const WORLEY_FBM_RANGE = vec2f(0.15, 0.85);

// Independent random numbers for a lattice cell, wrapped to `period` cells so the noise tiles.
// Offsets along z by a prime far beyond any period give each component its own stream.
fn random3(cell: vec3f, period: f32) -> vec3f {
  let wrapped = vec3u(cell - period * floor(cell / period));
  let stream = vec3u(0u, 0u, 7919u);
  return vec3f(hash3(wrapped), hash3(wrapped + stream), hash3(wrapped + 2u * stream));
}

// A uniformly distributed unit vector per lattice cell: Perlin's gradients.
fn gradient(cell: vec3f, period: f32) -> vec3f {
  let random = random3(cell, period);
  let z = random.x * 2.0 - 1.0;
  let azimuth = random.y * TAU;
  return vec3f(sqrt(1.0 - z * z) * vec2f(cos(azimuth), sin(azimuth)), z);
}

// Perlin gradient noise in [−1, 1] with the quintic fade (Perlin 2002); p in lattice cells.
fn perlin(p: vec3f, period: f32) -> f32 {
  let cell = floor(p);
  let f = p - cell;
  let fade = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  var corners: array<f32, 8>;
  for (var i = 0u; i < 8u; i++) {
    let corner = vec3f(vec3u(i, i >> 1u, i >> 2u) & vec3u(1u));
    corners[i] = dot(gradient(cell + corner, period), f - corner);
  }
  let x = mix(vec4f(corners[0], corners[2], corners[4], corners[6]), vec4f(corners[1], corners[3], corners[5], corners[7]), fade.x);
  let y = mix(x.xz, x.yw, fade.y);
  return mix(y.x, y.y, fade.z) * 1.15;
}

// Inverted cellular noise (Worley 1996): 1 on a feature point, falling to 0 about a cell away.
// One feature point per cell, so the 27 neighbouring cells always contain the nearest.
fn worley(p: vec3f, period: f32) -> f32 {
  let cell = floor(p);
  let f = p - cell;
  var nearest = 1.0;
  for (var i = 0u; i < 27u; i++) {
    let offset = vec3f(f32(i % 3u), f32((i / 3u) % 3u), f32(i / 9u)) - 1.0;
    let toPoint = offset + random3(cell + offset, period) - f;
    nearest = min(nearest, dot(toPoint, toPoint));
  }
  return 1.0 - sqrt(nearest);
}

fn perlinFbm(p: vec3f, frequency: f32) -> f32 {
  let octaves = vec3f(perlin(p * frequency, frequency), perlin(p * frequency * 2.0, frequency * 2.0), perlin(p * frequency * 4.0, frequency * 4.0));
  return dot(octaves, OCTAVE_WEIGHTS);
}

@compute @workgroup_size(4, 4, 4)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(volume);
  if (any(id >= size)) {
    return;
  }
  // Position across the volume in [0, 1); octave n repeats BASE_FREQUENCY · 2ⁿ times.
  let p = (vec3f(id) + 0.5) / vec3f(size);
  var cells: array<f32, 5>;
  for (var octave = 0u; octave < 5u; octave++) {
    let frequency = BASE_FREQUENCY * f32(1u << octave);
    cells[octave] = worley(p * frequency, frequency);
  }
  let worleyFbm = vec3f(
    dot(vec3f(cells[0], cells[1], cells[2]), OCTAVE_WEIGHTS),
    dot(vec3f(cells[1], cells[2], cells[3]), OCTAVE_WEIGHTS),
    dot(vec3f(cells[2], cells[3], cells[4]), OCTAVE_WEIGHTS),
  );
  // Dilate the Perlin billows by the Worley cells: rounded heaps with crisp gaps between them.
  let billows = saturate(perlinFbm(p, BASE_FREQUENCY) * 0.5 + 0.5);
  let perlinWorley = mix(worleyFbm.x, 1.0, billows);
  let r = (perlinWorley - PERLIN_WORLEY_RANGE.x) / (PERLIN_WORLEY_RANGE.y - PERLIN_WORLEY_RANGE.x);
  let gba = (worleyFbm - WORLEY_FBM_RANGE.x) / (WORLEY_FBM_RANGE.y - WORLEY_FBM_RANGE.x);
  textureStore(volume, id, saturate(vec4f(r, gba)));
}
