// The average lit share of the air around each view ray: the light-shaft layer's lit share
// (shafts.wgsl), averaged over blocks many lanes wide, however many fit the layer's target. The
// scene measures each ray's beam against it, so the shafts add contrast between lit and shaded
// lanes but no light overall, and upsamples it bilinearly, which blends neighbouring blocks into a
// smooth field.

@group(0) @binding(1) var shaftLayer: texture_2d<f32>;
@group(0) @binding(2) var shaftSampler: sampler;
@group(0) @binding(3) var shaftMean: texture_storage_2d<rgba16float, write>;

const TAP_STRIDE = 4.0;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(shaftMean);
  if (any(id.xy >= size)) {
    return;
  }
  let layer = vec2f(textureDimensions(shaftLayer));
  // Each bilinear tap averages a 2 × 2 quad of the layer's texels, every TAP_STRIDE texels: the
  // lanes are far wider, so this sparse grid still finds their mean.
  let block = vec2u(ceil(layer / vec2f(size) / TAP_STRIDE));
  let corner = vec2f(id.xy) * layer / vec2f(size);
  var sum = 0.0;
  for (var y = 0u; y < block.y; y++) {
    for (var x = 0u; x < block.x; x++) {
      let texel = corner + TAP_STRIDE * (vec2f(f32(x), f32(y)) + 0.5);
      sum += textureSampleLevel(shaftLayer, shaftSampler, texel / layer, 0.0).a;
    }
  }
  textureStore(shaftMean, id.xy, vec4f(sum / f32(block.x * block.y), 0.0, 0.0, 1.0));
}
