// The cloud layer: one jittered march per cell of the scene target (rgb = radiance,
// a = transmittance), at the pixel of the cell whose turn it is (sky/interleave.ts), after Horizon
// Zero Dawn (Schneider 2015). The scene pass reconstructs the other pixels from their history and
// accumulates every pixel's own marches over frames. The jitter is interleaved gradient noise over
// the scene target's pixels, strided by the golden ratio at each visit, so each pixel's successive
// jitters spread evenly over [0, 1) and their average converges quickly. A still sky then settles
// to a clean image instead of freezing one frame's noise pattern in place.

// The golden-ratio stride restarts every so many visits, keeping `visit × stride` exact in f32.
const JITTER_CYCLE = 1024u;

@fragment
fn main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let pixel = floor(position.xy) * u.cloudCell + u.cloudPhase + 0.5;
  let stride = GOLDEN_RATIO * f32(u32(u.cloudVisit) % JITTER_CYCLE);
  return clouds(viewRay(pixel), fract(interleavedGradientNoise(pixel) + stride));
}
