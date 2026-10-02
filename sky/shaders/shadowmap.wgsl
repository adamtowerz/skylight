// Draws the cloud shadow map (cloudshadow.wgsl): each texel marches its line through the cumulus
// from the key light's side, and keeps where the cloud begins, how dense it is and how much of it
// there is. Only the heaps' bulk, without their turrets or detail, which its long steps would alias.
//
// Its texels are lines fixed around the observer, which the heaps drift through, so what each
// stores must change smoothly as a heap's edge crosses it, or the lane it shades jumps by a
// texel: the front is where along the line the light is taken on average (each step's entry
// weighted by the light it takes), which slides as a thin heap in front thickens instead of
// leaping to it, and the mean density is weighted by density. Samples lie on a lattice along the
// light laid out from the region's middle and carried by the wind, so a heap is sampled at the
// same depths as it drifts. The march covers the line inside the cloud layer's top, from the
// region's far side toward the light, as far as the heaps whose shadows fall to the ground
// within the region (at least MIN_SHADOW_REACH from its middle), fading out over the last
// SHADOW_FADE so heaps drift in and out of reach unseen. Those are the heaps in and near view,
// whose lit gaps and shaded lanes the air shows as beams; beyond them lies a bank that would
// shade it all.
//
// The deck (deck.wgsl), when there is one, is a thin sheet at its base as far as its shadows go:
// its column is taken where the line climbs through the base, below the heaps, so the air under
// a whole deck is shaded and lit only beneath its gaps.

@group(0) @binding(7) var shadowMap: texture_storage_2d<rgba16float, write>;

const SHADOW_STEP = 0.5; // km
const MIN_SHADOW_REACH = 20.0; // km
const MAX_SHADOW_REACH = 80.0; // km
const SHADOW_FADE = 10.0; // km
// Enough for the longest line through the region and the reach.
const MAX_SHADOW_STEPS = 256.0;
// Deeper than this no light passes anyway; the cap keeps the premultiplied fronts in f16 range.
const MAX_SHADOW_DEPTH = 64.0;
// The sheet the deck's column is spread over, km.
const DECK_SHEET = 0.3;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(shadowMap);
  if (any(id.xy >= size)) {
    return;
  }
  let frame = cloudShadowFrame(keyLight().direction);
  let origin = shadowLine(frame, (vec2f(id.xy) + 0.5) / vec2f(size));
  let r = length(origin);
  let inside = raySphere(r, dot(origin, frame.toward) / r, u.bottomRadius + u.cloudTop);
  let region = SHADOW_RADIUS + u.cloudTop;
  // Along the light from the cloud base down to the ground: long under a low sun.
  let fall = u.cloudBottom / max(abs(frame.toward.y), 1e-3);
  let reach = clamp(fall, MIN_SHADOW_REACH, MAX_SHADOW_REACH);
  let near = max(inside.x, -region);
  let far = min(inside.y, reach);

  let extinction = EXTINCTION * u.cloudDensity;
  var depth = 0.0; // Σ density × step
  var squares = 0.0; // Σ density² × step
  var front = 0.0; // Σ entry of each step × the light it takes
  let phase = dot(drift(), frame.toward);
  let first = floor((far - phase) / SHADOW_STEP);
  let last = max(ceil((near - phase) / SHADOW_STEP), first - MAX_SHADOW_STEPS);
  for (var k = first; k >= last; k -= 1.0) {
    let s = k * SHADOW_STEP + phase;
    let p = origin + frame.toward * s;
    let h = heightFraction(p);
    if (h <= 0.0 || h >= 1.0) {
      continue;
    }
    let density = cumulusDensity(p, weatherAt(cloudSpace(p)), SHADOW_STEP) * (1.0 - smoothstep(reach - SHADOW_FADE, reach, s));
    if (density <= 0.0) {
      continue;
    }
    // Each sample stands for the step around it, entered from its side toward the light.
    let before = exp(-extinction * depth);
    depth += density * SHADOW_STEP;
    squares += density * density * SHADOW_STEP;
    front += (s + 0.5 * SHADOW_STEP) * (before - exp(-extinction * depth));
  }
  // The deck, where the line climbs up through its base toward the light.
  let b = dot(origin, frame.toward);
  let crossing = b * b - dot(origin, origin) + pow(u.bottomRadius + u.deckBase, 2.0);
  if (deckAbout() && crossing >= 0.0) {
    let s = sqrt(crossing) - b;
    let density = deckDepthAt(origin + frame.toward * s, SHADOW_STEP) / (extinction * DECK_SHEET);
    let before = exp(-extinction * depth);
    depth += density * DECK_SHEET;
    squares += density * density * DECK_SHEET;
    front += (s + 0.5 * DECK_SHEET) * (before - exp(-extinction * depth));
  }
  let opticalDepth = min(extinction * depth, MAX_SHADOW_DEPTH);
  let taken = 1.0 - exp(-extinction * depth);
  let meanExtinction = extinction * squares / max(depth, 1e-6);
  front /= max(taken, 1e-6);
  let stored = vec3f(front, meanExtinction, 1.0) * opticalDepth;
  textureStore(shadowMap, id.xy, vec4f(stored, 0.0));
}
