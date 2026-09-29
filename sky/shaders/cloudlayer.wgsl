// The cloud layer: one jittered march per cell of the scene target (rgb = radiance,
// a = transmittance), at the pixel of the cell whose turn it is (sky/interleave.ts), after Horizon
// Zero Dawn (Schneider 2015). The scene pass reconstructs the other pixels from their history and
// accumulates every pixel's own marches over frames. The jitter is the blue-noise mask over the
// cells plus the frame's offset, which strides each pixel's jitter by the golden ratio at every
// visit, so its successive jitters spread evenly over [0, 1) and their average converges quickly.
// A still sky then settles to a clean image instead of freezing one frame's noise pattern in place.

@fragment
fn main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let cell = floor(position.xy);
  let pixel = cell * u.cloudCell + u.cloudPhase + 0.5;
  return clouds(viewRay(pixel), fract(blueNoise(vec2u(cell)) + u.cloudJitter));
}
