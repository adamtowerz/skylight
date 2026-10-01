// Shared by every module: constants, hashing, the full-screen triangle, and the small
// structs that cross pass boundaries.

const PI = 3.14159265358979;
const TAU = 6.28318530717959;
// 1/φ. Adding it again and again to a value in [0, 1) (mod 1) visits the interval as evenly as
// any sequence can (a Weyl sequence), which makes it the ideal stride between successive jitters.
const GOLDEN_RATIO = 0.618033988749895;

// Rings the exposure pass splits the dome into, each an equal share of its cosine-weighted light.
const METERED_RINGS = 8u;

// Written by the exposure pass, read by post: a multiplier on scene radiance, and the sky dome's
// mean radiance (cosine-weighted) and its mean in rings from the zenith down, by sin² of the
// zenith angle: what a raindrop refracts, and what lights the grass it mirrors.
struct Exposure {
  value: f32,
  dome: vec3f,
  rings: array<vec4f, METERED_RINGS>,
}

// Rec. 709 luminance weights.
fn luminance(color: vec3f) -> f32 {
  return dot(color, vec3f(0.2126, 0.7152, 0.0722));
}

// PCG hash (Jarzynski & Olano 2020): cheap, well distributed integer hashing.
fn pcg(v: u32) -> u32 {
  let state = v * 747796405u + 2891336453u;
  let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

// Uniform random in [0, 1) from integer coordinates.
fn hash3(p: vec3u) -> f32 {
  return f32(pcg(p.x ^ pcg(p.y ^ pcg(p.z))) >> 8u) / 16777216.0;
}

fn hash2(p: vec2u) -> f32 {
  return hash3(vec3u(p, 0u));
}

// Interleaved gradient noise (Jimenez 2014): a blue-ish per-pixel pattern that dithers and
// jitters without visible structure.
fn interleavedGradientNoise(pixel: vec2f) -> f32 {
  return fract(52.9829189 * fract(dot(pixel, vec2f(0.06711056, 0.00583715))));
}

// One oversized triangle covers the whole target; fragment shaders use @builtin(position).
@vertex
fn fullscreen(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
  let corner = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
  return vec4f(corner * 2.0 - 1.0, 0.0, 1.0);
}
