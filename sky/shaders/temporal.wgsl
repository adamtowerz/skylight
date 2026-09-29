// Temporal reconstruction of the cloud layer (Karis 2014, "High Quality Temporal Supersampling";
// Salvi 2016, "An Excursion in Temporal Supersampling"), from a march at only one pixel of every
// cell each frame (Schneider 2015, "The Real-time Volumetric Cloudscapes of Horizon Zero Dawn").
// Each pixel keeps an exponential average of its own jittered marches. Last frame's average is
// fetched where the clouds now along this pixel's direction were seen, carried back along the
// wind and through last frame's camera, sharply, with a Catmull–Rom filter so that the slow
// reprojection never blurs. It is then clipped to the spread of this frame's marches around the
// pixel, so that as clouds churn and the light changes the past can lag by a little but never
// ghost. Every pixel is clipped against the same kind of box, marched this frame or not, so
// rejection never shows the pattern; the pixel whose turn it is then blends its fresh march in,
// and the others keep their clipped past. Where there is no past to trust (out of view, after a
// resize, while time is scrubbed) the pixels between the fresh marches are filled bilinearly from
// them. Clipping happens in YCoCg (plus transmittance), where a box around the neighbourhood hugs
// its colours far more tightly than in RGB.

@group(0) @binding(5) var cloudLayer: texture_2d<f32>; // one fresh march per cell
@group(0) @binding(6) var cloudHistory: texture_2d<f32>;
@group(0) @binding(7) var bilinear: sampler;

// Half-width of the clipping box in standard deviations of the neighbourhood. Its samples are
// interpolated from fewer marches, so they spread less than marches of their own would.
const CLIP_SIGMAS = 2.25;
// Weight of the past each time a pixel is marched: an average over about ten marches.
const HISTORY_WEIGHT = 0.9;

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

// Where a pixel centre lies among this frame's fresh marches, in cells: whole at a marched pixel.
fn cellPosition(pixel: vec2f) -> vec2f {
  return (pixel - 0.5 - u.cloudPhase) / u.cloudCell;
}

// Where the clouds seen along `dir` were last frame, as seen from here: the wind has carried them
// since, and at the heaps' middle height that drift is also close to the cirrus's in angle (it
// flies faster but higher).
fn driftedBack(dir: vec3f) -> vec3f {
  let height = u.bottomRadius + 0.5 * (u.cloudBottom + u.cloudTop);
  let distance = raySphere(observerRadius(), dir.y, height).y;
  let drift = u.cloudWind - u.previousCloudWind;
  return normalize(dir * distance - vec3f(drift.x, 0.0, drift.y));
}

fn freshAt(cell: vec2i) -> vec4f {
  let texel = clamp(cell, vec2i(0), vec2i(textureDimensions(cloudLayer)) - 1);
  return toYCoCg(textureLoad(cloudLayer, texel, 0));
}

// The fresh marches interpolated bilinearly, at a position in cells.
fn filledAt(cell: vec2f) -> vec4f {
  let uv = (cell + 0.5) / vec2f(textureDimensions(cloudLayer));
  return toYCoCg(textureSampleLevel(cloudLayer, bilinear, uv, 0.0));
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
    sum += textureSampleLevel(cloudHistory, bilinear, taps[i].xy, 0.0) * taps[i].z;
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

// `history` clipped to the spread of the fresh marches, reconstructed at the 3 × 3 pixels around
// `cell`: the box spans no more of the sky than it would with every pixel marched, so thin
// highlights are never averaged away with the sky a cell beyond them.
fn clipToNeighbourhood(history: vec4f, cell: vec2f) -> vec4f {
  var sum = vec4f(0.0);
  var squares = vec4f(0.0);
  for (var i = 0; i < 9; i++) {
    let neighbour = filledAt(cell + vec2f(f32(i % 3 - 1), f32(i / 3 - 1)) / u.cloudCell);
    sum += neighbour;
    squares += neighbour * neighbour;
  }
  let mean = sum / 9.0;
  let sigma = sqrt(max(squares / 9.0 - mean * mean, vec4f(0.0)));
  return clipToBox(history, mean, CLIP_SIGMAS * sigma);
}

// The cloud layer at pixel centre `pixel` (whose view direction is `dir`), averaged over recent
// frames.
fn accumulateClouds(pixel: vec2f, dir: vec3f) -> vec4f {
  let cell = cellPosition(pixel);
  let nearest = round(cell);
  let marched = all(cell == nearest);
  let current = select(filledAt(cell), freshAt(vec2i(nearest)), marched);
  let uv = previousUv(driftedBack(dir));
  if (u.historyTrust <= 0.0 || any(uv != saturate(uv))) {
    return fromYCoCg(current);
  }
  let history = clipToNeighbourhood(historyAt(uv), cell);
  let weight = u.historyTrust * select(1.0, HISTORY_WEIGHT, marched);
  return fromYCoCg(mix(current, history, weight));
}
