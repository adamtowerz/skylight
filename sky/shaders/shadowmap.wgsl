// Draws the cloud shadow map (cloudshadow.wgsl): each texel marches its line through the cumulus
// from the key light's side, and keeps where the cloud begins, how dense it is and how much of it
// there is. The heaps' shapes without their detail, as the clouds' own light march sees them.
//
// Samples lie on a lattice along the light that is fixed in the cloud field, like the texels
// across it, so a heap drifting through the map is sampled at the same points all the way and
// its shadow never flickers. The march covers the line inside the cloud layer's top, from the
// region's far side toward the light, as far as the heaps whose shadows fall to the ground within
// the region (at least MIN_SHADOW_REACH from its middle), fading out over the last SHADOW_FADE so
// heaps drift in and out of reach unseen. Those are the heaps in and near view, whose lit gaps
// and shaded lanes the air shows as beams; beyond them lies a bank that would shade it all.

@group(0) @binding(7) var shadowMap: texture_storage_2d<rgba16float, write>;

const SHADOW_STEP = 0.5; // km
const MIN_SHADOW_REACH = 20.0; // km
const MAX_SHADOW_REACH = 80.0; // km
const SHADOW_FADE = 10.0; // km
// Enough for the longest line through the region and the reach.
const MAX_SHADOW_STEPS = 256.0;
// Deeper than this no light passes anyway; the cap keeps the premultiplied fronts in f16 range.
const MAX_SHADOW_DEPTH = 64.0;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(shadowMap);
  if (any(id.xy >= size)) {
    return;
  }
  let frame = cloudShadowFrame(keyLight().direction, vec2f(size));
  let origin = shadowLine(frame, (vec2f(id.xy) + 0.5) / vec2f(size));
  let r = length(origin);
  let inside = raySphere(r, dot(origin, frame.toward) / r, u.bottomRadius + u.cloudTop);
  let region = SHADOW_RADIUS + u.cloudTop;
  // Along the light from the cloud base down to the ground: long under a low sun.
  let fall = u.cloudBottom / max(abs(frame.toward.y), 1e-3);
  let reach = frame.centre.z + clamp(fall, MIN_SHADOW_REACH, MAX_SHADOW_REACH);
  let near = max(inside.x, frame.centre.z - region);
  let far = min(inside.y, reach);

  var depth = 0.0; // Σ density × step
  var span = 0.0; // km of line inside cloud
  var front = 0.0;
  let first = floor(far / SHADOW_STEP);
  let last = max(ceil(near / SHADOW_STEP), first - MAX_SHADOW_STEPS);
  for (var k = first; k >= last; k -= 1.0) {
    let s = k * SHADOW_STEP;
    let p = origin + frame.toward * s;
    let h = heightFraction(p);
    if (h <= 0.0 || h >= 1.0) {
      continue;
    }
    let density = cumulusDensity(p, coverage(cloudSpace(p)), false) * (1.0 - smoothstep(reach - SHADOW_FADE, reach, s));
    if (density <= 0.0) {
      continue;
    }
    if (depth == 0.0) {
      front = s + 0.5 * SHADOW_STEP;
    }
    depth += density * SHADOW_STEP;
    span += SHADOW_STEP;
  }
  let extinction = EXTINCTION * u.cloudDensity;
  let opticalDepth = min(extinction * depth, MAX_SHADOW_DEPTH);
  let meanExtinction = extinction * depth / max(span, 1e-4);
  let stored = vec3f(front - frame.centre.z, meanExtinction, 1.0) * opticalDepth;
  textureStore(shadowMap, id.xy, vec4f(stored, 0.0));
}
