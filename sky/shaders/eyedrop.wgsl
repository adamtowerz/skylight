// Drops on the eye (eyedrops.ts): each a little lens of water lying on it, drawn by `post` over the
// frame. A drop sitting on a surface is a spherical cap, a plano-convex lens: a ray through it at a
// share ρ of its radius from the middle is bent toward its axis in proportion to the cap's slope
// there, which grows toward the rim faster than ρ (a sphere, not a paraboloid). The eye focuses on
// the sky, at infinity, so a lens on it maps directions rather than forming a sharp image of the
// drop: what the eye sees through it at offset d from its middle is the direction d(1 − k), k the
// lens's strength. A fresh drop is strong enough (k > 1) that the view through it is turned over
// and magnified, the sky about it upside down inside it; as it spreads and drains it flattens and
// the view through it rights itself and fades back into the sky. The drop is far out of focus, so
// its edge is soft and what it shows is blurred; toward the rim the light it gathers comes from
// ever further off, and more of it is reflected away (Fresnel), so the rim is darker. Screen-space
// refraction of the frame, after Rousseau, Jolivet & Ghazanfarpour 2006.

// Drops on the eye at most: `eyeDropSlots` in eyedrops.ts.
const EYE_DROPS = 6;
// The lens's strength when fresh, and how much stronger it is at the rim than at the middle.
const EYEDROP_POWER = 1.7;
const EYEDROP_RIM_POWER = 0.3;
// Width of the drop's soft edge, a share of its radius: the blur of a lens on the eye.
const EYEDROP_EDGE = 0.45;
// How wide the view through it is blurred, a share of its radius: at its middle, and more toward
// its rim, where the cap is steeper and its aberrations larger.
const EYEDROP_BLUR = 0.06;
const EYEDROP_RIM_BLUR = 2.5;
// How much of the light the rim loses, reflected away and gathered from far off the bright sky.
const EYEDROP_RIM = 0.12;

// The frame blurred over `radius` (uv) about `uv`: six taps about a seventh in the middle.
fn blurredScene(uv: vec2f, radius: vec2f) -> vec3f {
  var sum = textureSampleLevel(scene, sceneSampler, uv, 0.0).rgb;
  for (var i = 0; i < 6; i++) {
    let angle = f32(i) * TAU / 6.0;
    sum += textureSampleLevel(scene, sceneSampler, uv + radius * vec2f(cos(angle), sin(angle)), 0.0).rgb;
  }
  return sum / 7.0;
}

// The frame `behind` at the display pixel `pixel`, seen through any drops on the eye.
fn eyeDrops(pixel: vec2f, behind: vec3f) -> vec3f {
  let uv = pixel / u.outputResolution;
  let aspect = u.outputResolution.x / u.outputResolution.y;
  var seen = behind;
  for (var i = 0; i < EYE_DROPS; i++) {
    let drop = u.eyeDrops[i];
    if (drop.w <= 0.0) {
      continue;
    }
    // Offset from its middle in view heights, then in its radii.
    let offset = vec2f((uv.x - drop.x) * aspect, uv.y - drop.y);
    let rho = length(offset) / drop.z;
    if (rho >= 1.0 + EYEDROP_EDGE) {
      continue;
    }
    // Toward its edge the drop thins to nothing (its contact angle is small), and the blur of the
    // eye's focus spreads that over the soft edge: there it bends the light less and less.
    let inner = min(rho, 1.0);
    let thinning = 1.0 - smoothstep(1.0 - EYEDROP_EDGE, 1.0 + EYEDROP_EDGE, rho);
    let k = EYEDROP_POWER * drop.w * (1.0 + EYEDROP_RIM_POWER * inner * inner) * thinning;
    let through = offset * (1.0 - k);
    let looked = vec2f(drop.x + through.x / aspect, drop.y + through.y);
    let blur = EYEDROP_BLUR * (1.0 + EYEDROP_RIM_BLUR * inner * inner) * drop.z * vec2f(1.0 / aspect, 1.0);
    let rim = 1.0 - EYEDROP_RIM * drop.w * inner * inner * thinning;
    let lens = blurredScene(clamp(looked, vec2f(0.0), vec2f(1.0)), blur) * rim;
    seen = mix(seen, lens, thinning * saturate(4.0 * drop.w));
  }
  return seen;
}
