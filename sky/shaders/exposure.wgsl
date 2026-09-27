// Auto-exposure on the GPU, so it never round-trips through the CPU. One workgroup looks at
// the sky through the camera's frustum (a 16 × 16 grid of sky-view LUT samples), takes the
// log-average luminance, and exposes for it with a compressed key: exposure ∝ L^(−COMPRESSION)
// rather than L⁻¹, so night stays darker than day and a sunset keeps its glow instead of being
// normalised to grey. The result adapts smoothly over time, like an eye.

@group(0) @binding(5) var<storage, read_write> exposure: Exposure;

const GRID = 16u;
const SAMPLES = GRID * GRID;
// Exposure at a log-average sky luminance of 1.
const KEY = 0.17;
// 1 would fully normalise brightness; 0 would be a fixed exposure.
const COMPRESSION = 0.68;
// Adaptation rate, per second.
const ADAPTATION = 1.5;

var<workgroup> logLuminance: array<f32, SAMPLES>;

@compute @workgroup_size(GRID, GRID)
fn main(@builtin(local_invocation_id) id: vec3u, @builtin(local_invocation_index) index: u32) {
  let ndc = (vec2f(id.xy) + 0.5) / f32(GRID) * 2.0 - 1.0;
  let ray = u.cameraForward + ndc.x * u.tanHalfFov.x * u.cameraRight + ndc.y * u.tanHalfFov.y * u.cameraUp;
  logLuminance[index] = log2(max(luminance(skyViewRadiance(normalize(ray))), 1e-8));

  for (var stride = SAMPLES / 2u; stride > 0u; stride >>= 1u) {
    workgroupBarrier();
    if (index < stride) {
      logLuminance[index] += logLuminance[index + stride];
    }
  }
  if (index == 0u) {
    let average = logLuminance[0] / f32(SAMPLES);
    let desired = log2(KEY) - COMPRESSION * average;
    // The buffer starts zeroed: take the first frame's exposure as is.
    let previous = exposure.value;
    let adapted = select(desired, mix(log2(previous), desired, 1.0 - exp(-ADAPTATION * u.dt)), previous > 0.0);
    exposure.value = exp2(adapted);
  }
}
