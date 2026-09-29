// Cumulus: a shell of cloud between u.cloudBottom and u.cloudTop, raymarched front to back
// (Schneider 2015; Hillaire 2016). Density is the noise volume's Perlin–Worley heaps, masked by
// a low-frequency coverage ("weather") field and shaped by height: flat bases where rising air
// reaches its condensation level, rounded tops that climb higher where coverage is thicker. Finer
// Worley noise erodes the edges, wispy below and billowy above. Each step is lit by a short
// march toward the key light, with multiple scattering after Wrenninge et al. 2013 that reaches
// deeper under a grazing sun (sunset heaps glow through), and by skylight and grass light that
// fade with depth into the heap: shaded sides turn sky-blue, and thick cores go dark enough to
// stand out against the night.

// Horizontal extent of one tile of the noise volume, km: the heaps, their detail, the weather.
const SHAPE_TILE = 5.0;
const DETAIL_TILE = 0.8;
const WEATHER_TILE = 34.0;
// Where eroded heaps mostly fall; stretched over [0, 1], coverage c covers about c of the sky.
const HEAPS_RANGE = vec2f(0.1, 0.7);
// Cloud fills quickly past its boundary, as real cumulus does: nearly uniform inside, with
// a crisp edge for the detail to carve.
const BOUNDARY = 0.12;
// Density at the base relative to the body: droplets are still small where condensation begins.
const BASE_DENSITY = 0.5;
// How far local coverage strays from the mood's mean across the sky.
const WEATHER_CONTRAST = 1.2;
// How far the detail displaces the boundary, in units of the heaps field.
const EROSION = 0.3;
// Detail churns faster than the heaps it erodes.
const DETAIL_CHURN = 3.0;
// Extinction at unit density, km⁻¹ (real cumulus: tens per km).
const EXTINCTION = 36.0;

// View ray: more steps where the ray grazes the shell and crosses more of it. A heap turns opaque
// within a hundred metres of its edge, far less than a step, so where the ray enters one matters
// most, and marched at a fixed stride it falls on steps at nearly the same heights across
// neighbouring pixels: contour lines across the heaps, which neither the jitter nor the temporal
// average quite hides. So the field is taken to run linearly between samples and the threshold is
// integrated along each step exactly, and each step is lit where the light it scatters toward the
// eye comes from on average: a heap's opacity and light then change smoothly as its edge moves
// across the steps, and even a step that only grazes a heap sees it. That needs no extra samples,
// where searching for each edge in finer steps cost every ray marching in lockstep with one that
// searched (on the GPU, all of a group of neighbouring pixels).
const MIN_STEPS = 40.0;
const MAX_STEPS = 80.0;
const MAX_MARCH = 30.0; // km
// Stop once so little of the background shows through.
const OPAQUE = 0.01;

// Light ray: quadratically lengthening steps, dense near the sample where detail matters.
const LIGHT_STEPS = 5u;
const LIGHT_REACH = 2.0; // km

// Water droplets: a strong forward lobe (the silver lining toward the sun) and a weak backward
// one (Hillaire 2016's dual-lobe Henyey–Greenstein).
const FORWARD = 0.8;
const BACKWARD = -0.3;
const BACKWARD_WEIGHT = 0.3;
// Multiple-scattering octaves: each bounce keeps `energy` of the last, reaches `reach` times as
// deep and scatters `spread` times as anisotropically.
const OCTAVES = 4u;
const OCTAVE_ENERGY = 0.6;
const OCTAVE_SPREAD = 0.5;
// The reach under a high light keeps daylit cores from flooding with sunlight. Light diffused many
// times takes the shortest way in rather than the light's, and under a grazing sun that is down
// through the lit tops, not across kilometres of heap: there the deep octaves reach further, and
// the whole body of a sunset cloud glows. The key light is grazing below GRAZING.x and high above
// GRAZING.y (sines of ≈ 3° and 30°).
const OCTAVE_REACH = 0.4;
const GRAZING_OCTAVE_REACH = 0.27;
const GRAZING = vec2f(0.05, 0.5);
// Beer–powder (Schneider 2015): light must scatter in a while before it can come back out, so
// sun-facing edges seen from the shadowed side are darker than Beer's law alone says.
const POWDER = 0.6;
// Share of the ambient that is skylight slipping in through the cloud's nearby sides, which no
// depth into the heap hides. It is what tints shaded sides and bases blue in daylight.
const SIDE_SKYLIGHT = 0.5;
// Optical depth toward the key light over which a sample passes from the lit side of the cloud,
// which sees the whole sky, to the shaded side, which sees only the half turned from the light.
const SHADE_DEPTH = 8.0;

const DETAIL_WEIGHTS = vec3f(0.625, 0.25, 0.125);

fn cloudBase() -> f32 {
  return u.bottomRadius + u.cloudBottom;
}

// Height within the shell: 0 at the base, 1 at the top.
fn heightFraction(p: vec3f) -> f32 {
  return (length(p) - cloudBase()) / (u.cloudTop - u.cloudBottom);
}

// Where a position sits in the moving cloud field: carried by the wind, and sliding slowly
// through the noise volume's height so that heaps grow, merge and dissolve as they drift.
fn cloudSpace(p: vec3f) -> vec3f {
  return vec3f(p.x - u.cloudWind.x, length(p) - u.bottomRadius + u.cloudEvolution, p.z - u.cloudWind.y);
}

// Local coverage in [0, 1]: the mood's mean, broken into fields and gaps by the weather.
fn coverage(position: vec3f) -> f32 {
  let weather = sampleNoise(vec3f(position.xz, 0.5 * u.cloudEvolution) / WEATHER_TILE).r;
  return saturate(u.cloudCoverage + (weather - 0.5) * WEATHER_CONTRAST);
}

// Height fraction of the heaps' tops: they climb with coverage, from fair-weather puffs where it
// is thin to taller heaps where it is thick.
fn domeTop(cover: f32) -> f32 {
  return mix(0.45, 1.0, cover);
}

// Height fraction over which the heaps' flat bases fill in.
const BASE = 0.06;

// Flat base, then a rounded dome.
fn heightProfile(h: f32, cover: f32) -> f32 {
  let top = domeTop(cover);
  return smoothstep(0.0, BASE, h) * (1.0 - smoothstep(0.6 * top, top, h));
}

// How far past the threshold of cloud the field lies at a point: negative in clear air, and the
// cloud whole BOUNDARY past it. The heaps, shaped by height, form a continuous field; detail
// displaces it (wispy below, billowy above) before the sharp threshold turns it into cloud, so the
// detail carves the boundary itself. The light march skips the detail and takes its mean, and so
// does the view march where the detail could not carry the field across the threshold or out of
// the boundary: there the air is clear, or the cloud whole, whatever the detail says.
fn cumulusField(p: vec3f, cover: f32, detailed: bool) -> f32 {
  let h = heightFraction(p);
  let profile = heightProfile(h, cover);
  let threshold = 1.0 - cover;
  let displacement = 0.5 * EROSION; // the most the detail moves the field either way
  // The heaps never exceed their profile, so where even the detail could not carry it across the
  // threshold the noise is not read.
  if (profile + displacement <= threshold) {
    return profile - threshold;
  }
  let position = cloudSpace(p);
  let shape = sampleNoise(position / SHAPE_TILE);
  let eroded = remap(shape.r, 0.5 * dot(shape.gba, DETAIL_WEIGHTS), 1.0, 0.0, 1.0);
  let heaps = saturate(remap(eroded, HEAPS_RANGE.x, HEAPS_RANGE.y, 0.0, 1.0)) * profile;
  if (!detailed || heaps + displacement <= threshold || heaps - displacement >= threshold + BOUNDARY) {
    return heaps - threshold;
  }
  let churn = vec3f(0.0, DETAIL_CHURN * u.cloudEvolution, 0.0);
  let detail = dot(sampleNoise((position + churn) / DETAIL_TILE).gba, DETAIL_WEIGHTS);
  let billows = mix(detail, 1.0 - detail, saturate(h * 4.0));
  return heaps + EROSION * (0.5 - billows) - threshold;
}

// Density at the base relative to the body, at a point.
fn baseDensity(p: vec3f) -> f32 {
  return mix(BASE_DENSITY, 1.0, saturate(heightFraction(p) * 3.0));
}

// Density in [0, 1] at a point.
fn cumulusDensity(p: vec3f, cover: f32, detailed: bool) -> f32 {
  return saturate(cumulusField(p, cover, detailed) / BOUNDARY) * baseDensity(p);
}

// ∫ saturate(f / BOUNDARY) df: the threshold's ramp, integrated.
fn thresholdIntegral(field: f32) -> f32 {
  let ramp = saturate(field / BOUNDARY);
  return BOUNDARY * 0.5 * ramp * ramp + max(field - BOUNDARY, 0.0);
}

// The mean of saturate(f / BOUNDARY) along a step over which the field runs linearly from `a` to
// `b`: the threshold, which a heap crosses in far less than a step, integrated exactly between
// two samples instead of taken at one.
fn meanCloud(a: f32, b: f32) -> f32 {
  if (abs(b - a) < 1e-4) {
    return saturate(0.5 * (a + b) / BOUNDARY);
  }
  return (thresholdIntegral(b) - thresholdIntegral(a)) / (b - a);
}

// Optical depth from a sample toward the key light, through the bulk of the cloud. Samples are
// jittered within their steps like the view ray's, so step boundaries never show as contours.
fn opticalDepthToLight(p: vec3f, toLight: vec3f, cover: f32, jitter: f32) -> f32 {
  var depth = 0.0;
  var near = 0.0;
  for (var i = 1u; i <= LIGHT_STEPS; i++) {
    let far = LIGHT_REACH * pow(f32(i) / f32(LIGHT_STEPS), 2.0);
    depth += cumulusDensity(p + toLight * mix(near, far, jitter), cover, false) * (far - near);
    near = far;
  }
  return depth * EXTINCTION * u.cloudDensity;
}

// How much diffuse light reaches a sample through the cloud around it, from above (x: the sky) and
// from below (y: the grass). Two-stream diffuse transmission, 1 / (1 + ¾(1 − g)τ) (Bohren 1987),
// with τ estimated from the sample's own extinction and its depth below the dome's top or above
// the base: edges, where density is still rising, see nearly all of it; a thick heap's core very
// little, which is what lets clouds read darker than the sky behind them.
fn ambientReach(h: f32, cover: f32, extinction: f32) -> vec2f {
  let diffusion = 0.75 * (1.0 - FORWARD) * extinction * (u.cloudTop - u.cloudBottom);
  return 1.0 / (1.0 + diffusion * vec2f(max(domeTop(cover) - h, 0.0), h));
}

fn dropletPhase(cosTheta: f32, anisotropy: f32) -> f32 {
  return mix(henyeyGreenstein(cosTheta, FORWARD * anisotropy), henyeyGreenstein(cosTheta, BACKWARD * anisotropy), BACKWARD_WEIGHT);
}

// Direct light scattered toward the eye per unit illuminance, summed over bounces (Wrenninge et
// al. 2013, "Oz: The Great and Volumetric"): later octaves reach deeper with softer phases, so
// thick cloud glows white instead of turning grey.
fn scattering(opticalDepth: f32, cosTheta: f32, octaveReach: f32) -> f32 {
  var result = 0.0;
  var energy = 1.0;
  var reach = 1.0;
  var anisotropy = 1.0;
  for (var octave = 0u; octave < OCTAVES; octave++) {
    result += energy * dropletPhase(cosTheta, anisotropy) * exp(-reach * opticalDepth);
    energy *= OCTAVE_ENERGY;
    reach *= octaveReach;
    anisotropy *= OCTAVE_SPREAD;
  }
  let powder = 1.0 - POWDER * exp(-2.0 * opticalDepth) * (0.5 - 0.5 * cosTheta);
  return result * powder;
}

// Where along a uniform step of optical depth τ the light scattered toward the eye comes from on
// average, as a share of the step: ∫ s e^(−τs) ds / ∫ e^(−τs) ds over [0, 1], which is
// 1/τ − 1/(e^τ − 1): the middle of a thin step, and ever nearer the front of a thick one.
fn meanScatteringDepth(tau: f32) -> f32 {
  if (tau < 0.1) {
    return 0.5 - tau / 12.0; // the same, without the cancellation
  }
  return 1.0 / tau - 1.0 / (exp(tau) - 1.0);
}

// rgb: radiance toward the eye; a: transmittance.
fn cumulus(dir: vec3f, jitter: f32, lighting: CloudLighting) -> vec4f {
  let r = observerRadius();
  let enter = raySphere(r, dir.y, cloudBase()).y;
  let leave = min(raySphere(r, dir.y, u.bottomRadius + u.cloudTop).y, enter + MAX_MARCH);
  let steps = mix(MAX_STEPS, MIN_STEPS, saturate(dir.y));
  let stepLength = (leave - enter) / steps;
  let eye = vec3f(0.0, r, 0.0);
  let cosTheta = dot(dir, lighting.keyDirection);
  let octaveReach = mix(GRAZING_OCTAVE_REACH, OCTAVE_REACH, smoothstep(GRAZING.x, GRAZING.y, lighting.keyDirection.y));

  var radiance = vec3f(0.0);
  var seen = 1.0; // transmittance from the eye to the current sample
  var depth = 0.0; // opacity-weighted distance, for aerial perspective
  var lastField = 0.0; // how far past the threshold the last sample lay
  for (var i = 0.0; i < steps; i += 1.0) {
    let t = enter + (i + jitter) * stepLength;
    let p = eye + dir * t;
    let cover = coverage(cloudSpace(p));
    let field = cumulusField(p, cover, true);
    let before = lastField;
    lastField = field;
    if (field <= 0.0 && before <= 0.0) {
      continue;
    }
    // The step since the last sample, with the field taken to run linearly along it: its optical
    // depth, and the part of it in cloud, which where it enters or leaves a heap begins or ends
    // where the field crosses the threshold.
    let span = min(stepLength, t - enter);
    let cloudy = max(field, before);
    let clear = min(field, before);
    let inCloud = select(span, span * cloudy / (cloudy - clear), clear < 0.0);
    let start = select(t - inCloud, t - span, field <= 0.0);
    let opticalDepth = meanCloud(before, field) * baseDensity(p) * EXTINCTION * u.cloudDensity * span;
    let extinction = opticalDepth / max(inCloud, 1e-6);
    // The step is lit where the light it sends toward the eye comes from on average, which the
    // cloud in front of it pulls toward the step's start: a heap's rim, not its inside, catches
    // the light the eye sees there.
    let lit = start + inCloud * meanScatteringDepth(opticalDepth);
    let q = eye + dir * lit;
    let keyLight = lighting.keyIlluminance * transmittanceAt(q, lighting.keyDirection);
    // The light march's jitter strides by the golden ratio per step's length along the ray, so its
    // error averages out along the ray instead of repeating the pixel's pattern. It strides with
    // where the step is lit, not with the step's number, which changes where an edge crosses a
    // sample and would print the jump in the light march's error as a contour line.
    let lightJitter = fract(jitter + GOLDEN_RATIO * (lit - enter) / stepLength);
    let lightDepth = opticalDepthToLight(q, lighting.keyDirection, cover, lightJitter);
    let direct = keyLight * scattering(lightDepth, cosTheta, octaveReach);
    // Ambient: skylight from above and grass light from below, blended by height and each dimmed
    // by the cloud it diffuses through, plus skylight from the sides.
    let h = saturate(heightFraction(q));
    let reach = ambientReach(h, cover, extinction);
    let sky = mix(lighting.sky, lighting.shadedSky, 1.0 - exp(-lightDepth / SHADE_DEPTH));
    let ambient = mix(mix(lighting.ground * reach.y, sky * reach.x, sqrt(h)), sky, SIDE_SKYLIGHT);
    // Energy-conserving integration over the step (Hillaire 2016); droplets barely absorb, so
    // scattering ≈ extinction and the in-scattered light is simply (direct + ambient) × opacity.
    let opacity = 1.0 - exp(-opticalDepth);
    radiance += seen * opacity * (direct + ambient);
    depth += seen * opacity * t;
    seen *= 1.0 - opacity;
    if (seen < OPAQUE) {
      break;
    }
  }
  let layer = vec4f(radiance, seen);
  return throughAir(layer, dir, depth / max(1.0 - seen, 1e-4));
}
