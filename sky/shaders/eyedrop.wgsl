// Drops on the eye (eyedrops.ts): each a little lens of water lying on it, drawn by `post` over the
// frame, rain and all. A drop sitting on a surface is a spherical cap, a plano-convex lens: a ray
// through it at a share ρ of its radius from the middle is bent toward its axis in proportion to
// the cap's slope there, which grows toward the rim faster than ρ (a sphere, not a paraboloid). The
// eye focuses on the sky, at infinity, so a lens on it maps directions rather than forming a sharp
// image of the drop: what the eye sees through it at offset d from its middle is the direction
// d(1 − k), k the lens's strength. A beaded drop is strong enough (k > 1) that the view through it
// is turned over and magnified: the sky about it, its scud and the streaks falling across it, upside
// down inside it. Because k only grows toward the rim, that map never folds back on itself, so the
// view through the drop is one smooth image out to its edge, where the drop's own soft (defocused)
// outline fades it into the frame. Right at the contact line the water meets the eye in a steep
// meniscus that turns rays far aside, toward the dark ground and off the eye in reflection: a thin
// dark rim, with a thin bright one just inside where the cap gathers the bright sky. A drop that
// has slid leaves a short rivulet behind, a weak cylindrical lens that turns the view over across
// it. Screen-space refraction of the frame, after Rousseau, Jolivet & Ghazanfarpour 2006.

// Drops on the eye at most: `eyeDropSlots` in eyedrops.ts.
const EYE_DROPS = 6;
// The lens's strength once beaded, and how much stronger it is at the rim than at the middle.
const EYEDROP_POWER = 1.5;
const EYEDROP_RIM_POWER = 0.6;
// Width of the drop's soft edge, a share of its radius: the blur of a lens on the eye.
const EYEDROP_EDGE = 0.15;
// How wide the view through it is blurred, a share of its radius: at its middle, and more toward
// its rim, where the cap is steeper and its aberrations larger.
const EYEDROP_BLUR = 0.04;
const EYEDROP_RIM_BLUR = 1.5;
// The meniscus: where its dark and bright rims lie (shares of the radius), how wide they are, and
// how much light they take away and gather.
const MENISCUS_DARK = 0.97;
const MENISCUS_BRIGHT = 0.86;
const MENISCUS_WIDTH = 0.05;
const MENISCUS_SHADE = 0.45;
const MENISCUS_GLINT = 0.15;
// The trail: its width at the drop and at its far end (shares of the drop's radius), and its lens.
const TRAIL_WIDTH = vec2f(0.35, 0.12);
const TRAIL_POWER = 1.4;

// The frame blurred over `radius` (uv) about `uv`: six taps about a seventh in the middle.
fn blurredScene(uv: vec2f, radius: vec2f) -> vec3f {
  var sum = textureSampleLevel(scene, sceneSampler, uv, 0.0).rgb;
  for (var i = 0; i < 6; i++) {
    let angle = f32(i) * TAU / 6.0;
    sum += textureSampleLevel(scene, sceneSampler, uv + radius * vec2f(cos(angle), sin(angle)), 0.0).rgb;
  }
  return sum / 7.0;
}

// The meniscus's light at ρ (shares of the radius): dark at the contact line, bright just inside.
fn meniscus(rho: f32) -> f32 {
  let dark = (rho - MENISCUS_DARK) / MENISCUS_WIDTH;
  let bright = (rho - MENISCUS_BRIGHT) / MENISCUS_WIDTH;
  return 1.0 - MENISCUS_SHADE * exp(-dark * dark) + MENISCUS_GLINT * exp(-bright * bright);
}

// The frame at a display pixel as the drops on the eye leave it: `behind` seen through any trails,
// and the drop over it, if any (they seldom overlap; the last wins): where it looks (uv) and what
// it shows there before the rain. `post` draws the rain once, at `rainAt`: inside the drop, where
// the drop looks, so the streaks fall across its view too, turned over; outside it, at the pixel.
// The two meet under the meniscus's dark rim.
struct EyeDropView {
  seen: vec3f,
  rainAt: vec2f,
}

fn eyeDrops(pixel: vec2f, behind: vec3f) -> EyeDropView {
  let uv = pixel / u.outputResolution;
  let aspect = u.outputResolution.x / u.outputResolution.y;
  let toUv = vec2f(1.0 / aspect, 1.0);
  var seen = behind;
  var looked = uv;
  var lensBlur = vec2f(0.0);
  var shade = 1.0;
  var covered = 0.0;
  for (var i = 0; i < EYE_DROPS; i++) {
    let drop = u.eyeDrops[i];
    if (drop.w <= 0.0) {
      continue;
    }
    let shape = u.eyeDropShapes[i];
    let shows = saturate(4.0 * drop.w);
    // Offset from its middle in view heights, then in its radii.
    let offset = vec2f((uv.x - drop.x) * aspect, uv.y - drop.y);
    let rho = length(offset) / drop.z;
    let cover = 1.0 - smoothstep(1.0 - EYEDROP_EDGE, 1.0 + EYEDROP_EDGE, rho);
    if (cover > 0.0) {
      // Past the rim, inside its soft edge, it shows the view at the rim.
      let inner = min(rho, 1.0);
      let k = EYEDROP_POWER * shape.w * (1.0 + EYEDROP_RIM_POWER * inner * inner);
      let through = offset * (inner / max(rho, 1e-6)) * (1.0 - k);
      let blur = EYEDROP_BLUR * (1.0 + EYEDROP_RIM_BLUR * inner * inner) * drop.z * toUv;
      looked = drop.xy + through * toUv;
      lensBlur = blur;
      shade = meniscus(rho);
      covered = cover * shows;
      continue;
    }
    // The trail: distance to the segment back from its middle, and how far along it.
    let trail = shape.xy * vec2f(aspect, 1.0);
    let length2 = dot(trail, trail);
    if (length2 <= 0.0) {
      continue;
    }
    let along = saturate(dot(offset, trail) / length2);
    let across = offset - trail * along;
    let width = drop.z * mix(TRAIL_WIDTH.x, TRAIL_WIDTH.y, along);
    let sigma = length(across) / width;
    let wet = (1.0 - smoothstep(1.0 - 2.0 * EYEDROP_EDGE, 1.0 + 2.0 * EYEDROP_EDGE, sigma)) * shape.z * (1.0 - along * along);
    if (wet <= 0.0) {
      continue;
    }
    let crossed = clamp(uv - across * TRAIL_POWER * toUv, vec2f(0.0), vec2f(1.0));
    let lens = blurredScene(crossed, EYEDROP_BLUR * width * toUv) * meniscus(min(sigma, 1.0) * MENISCUS_DARK);
    seen = mix(seen, lens, wet * shows);
  }
  if (covered <= 0.0) {
    return EyeDropView(seen, pixel);
  }
  let at = clamp(looked, vec2f(0.0), vec2f(1.0));
  let lens = blurredScene(at, lensBlur) * shade;
  return EyeDropView(mix(seen, lens, covered), select(pixel, at * u.outputResolution, covered > 0.5));
}
