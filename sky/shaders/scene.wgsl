// The HDR scene: the sky behind, the clouds in front, linear radiance out. The cloud layer
// arrives sparse and noisy (one jittered march per cell) and is reconstructed and averaged over
// frames here; the sky is exact every frame, so the sun and moon never smear. Light shafts
// (shafts.wgsl) join the sky between the clouds, upsampled from the shaft layer: each ray's beam
// times how far its lit share strays from the average around it, so lit lanes brighten, shaded
// ones darken a little, and the sky around them keeps its glow. The averaged clouds go out as well, to become next
// frame's history. The stars are not drawn here but by `post`, at the display's resolution: the
// scene's alpha tells it how much of the sky beyond each pixel shows past the moon and clouds.

@group(0) @binding(8) var shaftLayer: texture_2d<f32>; // one texel per cell, like the cloud layer
@group(0) @binding(9) var shaftMean: texture_2d<f32>; // the average lit share, per block

// Shaded lanes darken only this much as lit ones brighten, the light scattered around the heaps
// filling their shadows in; they keep their hue, and never lose more than LANE_DEPTH of the sky.
const SHADE = 0.5;
const LANE_DEPTH = 0.3;
// Lit lanes meet the sky with a soft shoulder, light / (1 + light / sky), like film's: a dim beam
// at dusk shows in full, and the brightest, beside the sun, at most double the air's own light.

// The shaft layer averaged over the 6 × 6 texels around `uv`, in nine bilinear taps: the march's
// jitter, interleaved gradient noise, averages out over just such a neighbourhood, and the beams
// are far wider.
fn shaftsAt(uv: vec2f) -> vec4f {
  let texel = 1.0 / vec2f(textureDimensions(shaftLayer));
  var sum = vec4f(0.0);
  for (var i = 0; i < 9; i++) {
    let offset = vec2f(f32(i % 3 - 1), f32(i / 3 - 1)) * 2.0;
    sum += textureSampleLevel(shaftLayer, bilinear, uv + offset * texel, 0.0);
  }
  return sum / 9.0;
}

struct Scene {
  @location(0) radiance: vec4f,
  @location(1) clouds: vec4f,
}

@fragment
fn main(@builtin(position) position: vec4f) -> Scene {
  let dir = viewRay(position.xy);
  let clouds = accumulateClouds(position.xy, dir);
  let shaftUv = position.xy / (u.cloudCell * vec2f(textureDimensions(shaftLayer)));
  let beams = shaftsAt(shaftUv);
  let lit = beams.a - textureSampleLevel(shaftMean, bilinear, position.xy / u.resolution, 0.0).r;
  let dome = skyRadiance(dir);
  let air = dome.rgb;
  let brightness = max(luminance(air), 1e-9);
  let light = beams.rgb * max(lit, 0.0);
  let shade = min(SHADE * luminance(beams.rgb) * max(-lit, 0.0) / brightness, LANE_DEPTH);
  let sky = air * (1.0 - shade) + light / (1.0 + luminance(light) / brightness);
  // Alpha: the view to space past the moon and the clouds, for the stars `post` draws.
  return Scene(vec4f(sky * clouds.a + clouds.rgb, dome.a * clouds.a), clouds);
}
