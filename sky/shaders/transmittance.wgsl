// Transmittance LUT: the fraction of light surviving from each (r, μ) to space, integrated once
// per texel so every other pass reads it in one fetch (Hillaire 2020, after Bruneton 2008).

@group(0) @binding(5) var lut: texture_storage_2d<rgba16float, write>;

const STEPS = 40;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(lut);
  if (any(id.xy >= size)) {
    return;
  }
  let ray = transmittanceRay(texelToUnit(id.xy, size));
  let r = ray.x;
  let mu = ray.y;
  let dt = raySphere(r, mu, u.topRadius).y / f32(STEPS);

  // Midpoint rule over the optical depth; the altitude profile is smooth enough for 40 steps.
  var opticalDepth = vec3f(0.0);
  for (var i = 0; i < STEPS; i++) {
    let rt = radiusAlong(r, mu, (f32(i) + 0.5) * dt);
    opticalDepth += medium(rt - u.bottomRadius).extinction * dt;
  }
  textureStore(lut, id.xy, vec4f(exp(-opticalDepth), 1.0));
}
