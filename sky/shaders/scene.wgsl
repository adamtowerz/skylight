// The HDR scene: the sky behind, the clouds in front, linear radiance out. The cloud layer
// arrives sparse and noisy (one jittered march per cell) and is reconstructed and averaged over
// frames here; the sky is exact every frame, so the sun, moon and stars never smear. The averaged
// clouds go out as well, to become next frame's history.

struct Scene {
  @location(0) radiance: vec4f,
  @location(1) clouds: vec4f,
}

@fragment
fn main(@builtin(position) position: vec4f) -> Scene {
  let dir = viewRay(position.xy);
  let clouds = accumulateClouds(position.xy, dir);
  return Scene(vec4f(skyRadiance(dir) * clouds.a + clouds.rgb, 1.0), clouds);
}
