// The cloud layer: one jittered march per pixel (rgb = radiance, a = transmittance), which the
// scene pass accumulates over frames. The jitter is interleaved gradient noise, blue-ish across
// the screen, strided by the golden ratio every frame, so each pixel's successive jitters spread
// evenly over [0, 1) and their average converges quickly. A still sky then settles to a clean
// image instead of freezing one frame's noise pattern in place.

// The golden-ratio stride restarts every so many frames, keeping `frame × stride` exact in f32.
const JITTER_CYCLE = 1024u;

@fragment
fn main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let stride = GOLDEN_RATIO * f32(u32(u.frame) % JITTER_CYCLE);
  return clouds(viewRay(position.xy), fract(interleavedGradientNoise(position.xy) + stride));
}
