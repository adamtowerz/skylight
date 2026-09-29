// The blue-noise mask (sky/bluenoise.ts): a 64 × 64 tile of ranks in [0, 1) so evenly spread
// that neighbouring pixels always take values far apart. Tiled over a target, it jitters
// raymarches with an error the eye barely sees.

@group(0) @binding(9) var blueNoiseMask: texture_2d<f32>;

fn blueNoise(texel: vec2u) -> f32 {
  return textureLoad(blueNoiseMask, texel % textureDimensions(blueNoiseMask), 0).r;
}
