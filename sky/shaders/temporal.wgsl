// Temporal accumulation of the cloud layer (Karis 2014, "High Quality Temporal Supersampling";
// Salvi 2016, "An Excursion in Temporal Supersampling"). Each pixel keeps an exponential average
// of its jittered cloud marches: last frame's average is fetched where this pixel's direction was
// (`previousUv`), sharply, with a Catmull–Rom filter so that the slow reprojection never blurs,
// then clipped to the spread of this frame's 3 × 3 neighbourhood, so that as clouds drift and the
// light changes the past can lag by a little but never ghost. Clipping happens in YCoCg (plus
// transmittance), where a box around the neighbourhood hugs its colours far more tightly than in
// RGB.

@group(0) @binding(5) var cloudLayer: texture_2d<f32>;
@group(0) @binding(6) var cloudHistory: texture_2d<f32>;
@group(0) @binding(7) var historySampler: sampler;

// Half-width of the clipping box in standard deviations of the neighbourhood.
const CLIP_SIGMAS = 1.25;

fn toYCoCg(layer: vec4f) -> vec4f {
  let c = layer.rgb;
  return vec4f(dot(c, vec3f(0.25, 0.5, 0.25)), dot(c, vec3f(0.5, 0.0, -0.5)), dot(c, vec3f(-0.25, 0.5, -0.25)), layer.a);
}

fn fromYCoCg(layer: vec4f) -> vec4f {
  let y = layer.x;
  let co = layer.y;
  let cg = layer.z;
  return vec4f(y + co - cg, y + cg, y - co - cg, layer.a);
}

fn currentAt(pixel: vec2i) -> vec4f {
  let texel = clamp(pixel, vec2i(0), vec2i(textureDimensions(cloudLayer)) - 1);
  return toYCoCg(textureLoad(cloudLayer, texel, 0));
}

// Catmull–Rom history lookup in five bilinear taps (Jimenez 2016, "Filmic SMAA"): the four corner
// taps carry little weight and are dropped, and the rest renormalised.
fn historyAt(uv: vec2f) -> vec4f {
  let size = vec2f(textureDimensions(cloudHistory));
  let position = uv * size;
  let centre = floor(position - 0.5) + 0.5;
  let f = position - centre;
  let f2 = f * f;
  let f3 = f2 * f;
  let w0 = f2 - 0.5 * (f3 + f);
  let w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
  let w3 = 0.5 * (f3 - f2);
  let w2 = 1.0 - w0 - w1 - w3;
  // The middle two weights share one bilinear tap, placed between their texels in proportion.
  let w12 = w1 + w2;
  let t0 = (centre - 1.0) / size;
  let t12 = (centre + w2 / w12) / size;
  let t3 = (centre + 2.0) / size;
  let taps = array(
    vec3f(t12.x, t0.y, w12.x * w0.y),
    vec3f(t0.x, t12.y, w0.x * w12.y),
    vec3f(t12.x, t12.y, w12.x * w12.y),
    vec3f(t3.x, t12.y, w3.x * w12.y),
    vec3f(t12.x, t3.y, w12.x * w3.y),
  );
  var sum = vec4f(0.0);
  var weight = 0.0;
  for (var i = 0; i < 5; i++) {
    sum += textureSampleLevel(cloudHistory, historySampler, taps[i].xy, 0.0) * taps[i].z;
    weight += taps[i].z;
  }
  return toYCoCg(sum / weight);
}

// Pulls `history` toward the box's centre along the line between them until it lies inside
// (Playdead's clip, INSIDE 2016): unlike a per-axis clamp, it keeps the hue it had.
fn clipToBox(history: vec4f, centre: vec4f, extent: vec4f) -> vec4f {
  let offset = history - centre;
  let units = abs(offset) / max(extent, vec4f(1e-7));
  let furthest = max(max(units.x, units.y), max(units.z, units.w));
  return select(history, centre + offset / furthest, furthest > 1.0);
}

// The cloud layer at `pixel` (whose view direction is `dir`), averaged over recent frames.
fn accumulateClouds(pixel: vec2i, dir: vec3f) -> vec4f {
  let current = currentAt(pixel);
  let uv = previousUv(dir);
  if (u.historyWeight <= 0.0 || any(uv != saturate(uv))) {
    return fromYCoCg(current);
  }
  var sum = vec4f(0.0);
  var squares = vec4f(0.0);
  for (var i = 0; i < 9; i++) {
    let neighbour = currentAt(pixel + vec2i(i % 3 - 1, i / 3 - 1));
    sum += neighbour;
    squares += neighbour * neighbour;
  }
  let mean = sum / 9.0;
  let sigma = sqrt(max(squares / 9.0 - mean * mean, vec4f(0.0)));
  let history = clipToBox(historyAt(uv), mean, CLIP_SIGMAS * sigma);
  return fromYCoCg(mix(current, history, u.historyWeight));
}
