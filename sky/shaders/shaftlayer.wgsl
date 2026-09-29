// The light-shaft layer: the beams of sunlight through the gaps between the heaps (shafts.wgsl),
// at one pixel per cell of the scene target, like the cloud layer. Beams are soft enough that the
// scene upsamples them bilinearly, which quarters the cost of the march. The jitter is the
// blue-noise mask over the layer's pixels, fixed in time, so a still sky holds perfectly still.

@fragment
fn main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let texel = floor(position.xy);
  return beams(viewRay((texel + 0.5) * u.cloudCell), blueNoise(vec2u(texel)));
}
