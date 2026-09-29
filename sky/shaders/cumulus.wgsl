// Cumulus: a shell of cloud between u.cloudBottom and u.cloudTop, raymarched front to back
// (Schneider 2015; Hillaire 2016). Density follows Schneider's Nubis (2017): the noise volume's
// Perlin–Worley heaps, masked by a low-frequency weather field that sets both coverage and how
// tall the heaps grow (fair-weather puffs, and towering congestus at the hearts of its convection
// cells as the mood allows), shaped by a height gradient into domes that each heap's own core
// pushes up. The condensation level cuts every base flat; Worley turrets bulge from the flanks
// and tops (the cauliflower), and finer Worley detail erodes the edges, wispy below and billowy
// above. Every lookup resolves only the features its sample can, so nothing aliases into
// sparkle as the heaps drift. The field is dense (extinction as in real cumulus), which keeps
// edges crisp and lets thick heaps shade their own bases and crevices. Each step is lit by a short
// march toward the key light, with multiple scattering after Wrenninge et al. 2013 that reaches
// deeper under a grazing sun (sunset heaps glow through), and by skylight and grass light that
// fade with depth into the heap: shaded sides turn sky-blue, and thick cores go dark enough to
// stand out against the night.

// Horizontal extent of one tile of the noise volume, km: the heaps, their detail, the weather.
const SHAPE_TILE = 5.0;
const DETAIL_TILE = 0.8;
const WEATHER_TILE = 34.0;
// Where eroded heaps mostly fall; stretched so that coverage c covers about c of the sky. Their
// cores are left to rise past 1 rather than clipped flat, so that each heap's top follows its own
// billows instead of the same smooth dome.
const HEAPS_RANGE = vec2f(0.1, 0.7);
const MAX_HEAPS = 1.5; // the stretched range's top, (1 − 0.1) / (0.7 − 0.1)
// Cloud fills quickly past its boundary, as real cumulus does: nearly uniform inside, with
// a crisp edge for the detail to carve.
const BOUNDARY = 0.06;
// How far the heaps field typically changes per km across a heap's edge, in its own units.
const FIELD_CHANGE = 0.2;
// Density at the base relative to the body: droplets are still small where condensation begins.
const BASE_DENSITY = 0.7;
// How far local coverage strays from the mood's mean across the sky.
const WEATHER_CONTRAST = 1.2;
// Height fraction of fair-weather tops, where coverage is thin and where it is thick.
const FAIR_TOPS = vec2f(0.4, 0.7);
// Where in the weather's convection cells (its inverted Worley, 1 at their hearts) heaps tower.
const TOWER_CELLS = vec2f(0.3, 0.7);
// Height fraction over which air turns to whole cloud above the lifting condensation level, where
// rising air first condenses: the heaps' flat bases.
const BASE = 0.01;
// How far the turrets (the shape's finest Worley, cells of ≈ 300 m) bulge from the heaps, and how
// far the finer detail displaces their boundary, in units of the heaps field.
const TURRETS = 0.5;
const EROSION = 0.5;
// Detail churns faster than the heaps it erodes.
const DETAIL_CHURN = 3.0;
// Extinction at unit density, km⁻¹ (real cumulus: tens per km).
const EXTINCTION = 75.0;

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
const OCTAVE_REACH = 0.35;
const GRAZING_OCTAVE_REACH = 0.21;
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

// Typical spacing of the turrets and of the detail, km: their Worley fBm starts at 16 and at 4
// cells across a tile, with two finer octaves above each.
const TURRET_SPACING = SHAPE_TILE / 32.0;
const DETAIL_SPACING = DETAIL_TILE / 8.0;

// How much of features `spacing` apart a sample standing for `footprint` km resolves: all where
// several samples span one, none where one spans most of it. Unresolved features would alias,
// crawling and sparkling as the heaps drift, so they give way to their mean. That is what lets one
// field serve every lookup: the view ray's cells resolve all of it close by, the light march's
// lengthening steps the turrets near each sample, the shadow map's long steps only the heaps.
fn resolved(spacing: f32, footprint: f32) -> f32 {
  return 1.0 - smoothstep(0.25 * spacing, 0.75 * spacing, footprint);
}

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

// The weather over a point of the layer, in the manner of Schneider's weather map: how much of the
// sky is cloud there, and the height fraction its heaps' tops reach.
struct Weather {
  cover: f32,
  top: f32,
}

// Local coverage is the mood's mean, broken into fields and gaps. Heaps climb with it, from
// fair-weather puffs where it is thin to taller heaps where it is thick, and at the hearts of the
// weather's convection cells, where the air rises fastest, they tower as far as the mood allows.
fn weatherAt(position: vec3f) -> Weather {
  let weather = sampleNoise(vec3f(position.xz, 0.5 * u.cloudEvolution) / WEATHER_TILE);
  let cover = saturate(u.cloudCoverage + (weather.r - 0.5) * WEATHER_CONTRAST);
  let towering = u.cloudTowers * smoothstep(TOWER_CELLS.x, TOWER_CELLS.y, weather.g);
  return Weather(cover, mix(mix(FAIR_TOPS.x, FAIR_TOPS.y, cover), 1.0, towering));
}

// A dome that the heaps' cores push up into (Schneider 2017's cumulus height gradient): the
// higher a heap's own field, the higher its top.
fn heightProfile(h: f32, top: f32) -> f32 {
  let rise = h / top;
  return saturate(1.0 - rise * rise * rise);
}

// The field below which no air has yet condensed: a level plane that cuts every heap's base flat
// and smooth, whatever the detail does to its flanks.
fn condensationField(h: f32) -> f32 {
  return BOUNDARY * h / BASE;
}

// How far past the threshold of cloud the field lies at a point: negative in clear air, and the
// cloud whole BOUNDARY past it. The heaps, shaped by height, form a continuous field; turrets
// bulge from it, and detail displaces it (wispy below, billowy above) before the sharp threshold
// turns it into cloud, so the detail carves the boundary itself. A sample standing for `footprint`
// km takes the mean of the features it cannot resolve, and the detail is not read where it could
// not carry the field across the threshold or out of the boundary: there the air is clear, or the
// cloud whole, whatever the detail says.
fn cumulusField(p: vec3f, weather: Weather, footprint: f32) -> f32 {
  let h = heightFraction(p);
  let rise = h / weather.top;
  let profile = heightProfile(h, weather.top);
  let threshold = 1.0 - weather.cover;
  let turrets = TURRETS * resolved(TURRET_SPACING, footprint);
  let erosion = EROSION * resolved(DETAIL_SPACING, footprint);
  let detailReach = 0.5 * erosion; // the most the detail moves the field either way
  // The heaps never exceed their profile, so where even turrets and detail could not carry them
  // across the threshold the noise is not read.
  let base = condensationField(h);
  if (MAX_HEAPS * profile + 0.5 * turrets + detailReach <= threshold || base <= 0.0) {
    return min(MAX_HEAPS * profile - threshold, base);
  }
  let position = cloudSpace(p);
  let shape = sampleNoise(position / SHAPE_TILE);
  let eroded = remap(shape.r, 0.5 * dot(shape.gba, DETAIL_WEIGHTS), 1.0, 0.0, 1.0);
  let heaps = max(remap(eroded, HEAPS_RANGE.x, HEAPS_RANGE.y, 0.0, 1.0), 0.0) * profile;
  // Cauliflower: rounded turrets bulge from the flanks and tops and lobe the base's outline; the
  // condensation level still cuts it flat.
  let body = heaps + turrets * (shape.a - 0.5);
  if (erosion <= 0.0 || body + detailReach <= threshold || body - detailReach >= threshold + BOUNDARY) {
    return min(body - threshold, base);
  }
  let churn = vec3f(0.0, DETAIL_CHURN * u.cloudEvolution, 0.0);
  let detail = dot(sampleNoise((position + churn) / DETAIL_TILE).gba, DETAIL_WEIGHTS);
  let billows = mix(detail, 1.0 - detail, smoothstep(0.1, 0.4, rise));
  return min(body + erosion * (0.5 - billows) - threshold, base);
}

// Density at the base relative to the body, at a point.
fn baseDensity(p: vec3f) -> f32 {
  return mix(BASE_DENSITY, 1.0, saturate(heightFraction(p) * 3.0));
}

// Density in [0, 1] at a sample standing for `footprint` km. Across a long sample the field
// sweeps through the threshold's ramp and beyond, so its mean density rises gently rather than
// jumping as an edge crosses the sample: the ramp is widened by how far the field typically
// changes over the footprint. Where the light march and shadow map step far, heaps then shade
// smoothly as they drift instead of sparkling and flickering.
fn cumulusDensity(p: vec3f, weather: Weather, footprint: f32) -> f32 {
  let ramp = BOUNDARY + FIELD_CHANGE * footprint;
  return saturate(cumulusField(p, weather, footprint) / ramp) * baseDensity(p);
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
fn opticalDepthToLight(p: vec3f, toLight: vec3f, weather: Weather, jitter: f32) -> f32 {
  var depth = 0.0;
  var near = 0.0;
  for (var i = 1u; i <= LIGHT_STEPS; i++) {
    let far = LIGHT_REACH * pow(f32(i) / f32(LIGHT_STEPS), 2.0);
    depth += cumulusDensity(p + toLight * mix(near, far, jitter), weather, far - near) * (far - near);
    near = far;
  }
  return depth * EXTINCTION * u.cloudDensity;
}

// How much diffuse light reaches a sample through the cloud around it, from above (x: the sky) and
// from below (y: the grass). Two-stream diffuse transmission, 1 / (1 + ¾(1 − g)τ) (Bohren 1987),
// with τ estimated from the sample's own extinction and its depth below the dome's top or above
// the base: edges, where density is still rising, see nearly all of it; a thick heap's core very
// little, which is what lets clouds read darker than the sky behind them.
fn ambientReach(h: f32, top: f32, extinction: f32) -> vec2f {
  let diffusion = 0.75 * (1.0 - FORWARD) * extinction * (u.cloudTop - u.cloudBottom);
  return 1.0 / (1.0 + diffusion * vec2f(max(top - h, 0.0), h));
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
  // Across the sky one march spans a cell of pixels, this many km per km along the ray.
  let footprint = u.cloudCell * 2.0 * u.tanHalfFov.y / u.resolution.y;
  let octaveReach = mix(GRAZING_OCTAVE_REACH, OCTAVE_REACH, smoothstep(GRAZING.x, GRAZING.y, lighting.keyDirection.y));

  var radiance = vec3f(0.0);
  var seen = 1.0; // transmittance from the eye to the current sample
  var depth = 0.0; // opacity-weighted distance, for aerial perspective
  var lastField = 0.0; // how far past the threshold the last sample lay
  for (var i = 0.0; i < steps; i += 1.0) {
    let t = enter + (i + jitter) * stepLength;
    let p = eye + dir * t;
    let weather = weatherAt(cloudSpace(p));
    let field = cumulusField(p, weather, t * footprint);
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
    let lightDepth = opticalDepthToLight(q, lighting.keyDirection, weather, lightJitter);
    let direct = keyLight * scattering(lightDepth, cosTheta, octaveReach);
    // Ambient: skylight from above and grass light from below, blended by height and each dimmed
    // by the cloud it diffuses through, plus skylight from the sides.
    let h = saturate(heightFraction(q));
    let reach = ambientReach(h, weather.top, extinction);
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
