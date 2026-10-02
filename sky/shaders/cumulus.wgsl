// Cumulus: a shell of cloud between u.cloudBottom and u.cloudTop, raymarched front to back
// (Schneider 2015; Hillaire 2016). Density follows Schneider's Nubis (2017): the noise volume's
// Perlin–Worley heaps, masked by a low-frequency weather field that sets both coverage and how
// tall the heaps grow (fair-weather puffs, and towering congestus at the hearts of its convection
// cells as the mood allows), shaped by a height gradient into domes that each heap's own core
// pushes up, and sheared about by the weather so that each heap's outline is its own. The
// condensation level cuts every base flat; broad Worley turrets swell the flanks and tops, merging
// into one body rather than a pile of lobes, and finer Worley detail erodes the edges, wispy below
// and billowy above, both kept close to the heaps' own bodies so they never scatter into flecks.
// Every lookup resolves only the features its sample can, so nothing aliases into sparkle as the
// heaps drift. Density rises from a soft, translucent rim into a core as dense as real cumulus, so
// heaps have soft volume yet shade their own bases and crevices. Each step is lit by a short march
// toward the key light and one up through the column above it, with multiple scattering after
// Wrenninge et al. 2013 that comes in along whichever way brings more: along the light, or diffused
// down from the sunlit crown (Bohren 1987) and in from the sunlit flanks, dying away across the
// heap as a slab's diffusion mode does. So under a low sun the flanks facing it blaze, the bases
// beneath flat heaps sink into their own shade and those of tall banks glow a dim gold far in from
// the flanks, and skylight and grass light fade with depth into the heap too: shaded sides turn
// sky-blue, and thick cores go dark enough to stand out against the night.

// Horizontal extent of one tile of the noise volume, km: the heaps, their detail, the weather.
const SHAPE_TILE = 5.0;
const DETAIL_TILE = 0.8;
const WEATHER_TILE = 34.0;
// Where eroded heaps mostly fall; stretched so that coverage c covers about c of the sky. Their
// cores are left to rise past 1 rather than clipped flat, so that each heap's top follows its own
// billows instead of the same smooth dome.
const HEAPS_RANGE = vec2f(0.1, 0.7);
const MAX_HEAPS = 1.5; // the stretched range's top, (1 − 0.1) / (0.7 − 0.1)
// Density past the threshold of cloud, in units of the heaps field: it rises to a translucent rim
// at BOUNDARY, a few hundred metres in, so that outlines thin out rather than end in a cut, then
// gradually to the core at CORE. Real cumulus thicken inward like this, which gives each heap soft volume, light
// fading into shadow across it, rather than the flat face of a uniformly dense one.
const BOUNDARY = 0.16;
const CORE = 0.35;
const RIM = 0.3; // share of the core's density the rim reaches
// How far the heaps field typically changes per km across a heap's edge, in its own units.
const FIELD_CHANGE = 0.2;
// Density at the base relative to the body: droplets are still small where condensation begins.
const BASE_DENSITY = 0.7;
// How far local coverage strays from the mood's mean across the sky.
const WEATHER_CONTRAST = 1.2;
// The deck's cover by which no heap is left beside it (weatherAt).
const DECK_CAPS_HEAPS = 0.95;
// How far a closing deck lowers the heaps' tops, and the power of their domes once it has spread
// them out (3 for heaps free to rise).
const CAPPED_TOPS = 0.4;
const SPREAD_DOME = 1.2;
// Height fraction of fair-weather tops, where coverage is thin and where it is thick.
const FAIR_TOPS = vec2f(0.4, 0.7);
// Where in the weather's convection cells (its inverted Worley, 1 at their hearts) heaps tower.
const TOWER_CELLS = vec2f(0.3, 0.7);
// How far the weather shears the heaps' shapes about, km.
const WARP = 0.7;
// Height fraction over which air turns to whole cloud above the lifting condensation level, where
// rising air first condenses: the heaps' flat bases.
const BASE = 0.01;
// How far the turrets (the shape's middle Worley, cells of ≈ 600 m) swell the heaps, and how
// far the finer detail displaces their boundary, in units of the heaps field: most at the crowns,
// which boil, least low down, where fraying would shred the heaps into flecks.
const TURRETS = 0.35;
const EROSION = vec2f(0.3, 0.56); // low on a heap, and at its crown
// How far past the heaps' own smooth boundary turrets and detail may carry it, low on a heap and
// at its crown: they lobe and fray coherent heaps, but never raise detached flecks out of clear
// air, and boil up freely only from the crowns, where the air rises fastest.
const ATTACHED = vec2f(0.05, 0.2);
// Detail churns faster than the heaps it erodes.
const DETAIL_CHURN = 3.0;
// Extinction at unit density, km⁻¹ (real cumulus: tens per km).
const EXTINCTION = 60.0;

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
// The reach under a high light keeps daylit cores from flooding with sunlight. Under a grazing one
// the light runs in sideways, just above the flat base, through which diffused light keeps leaking
// out (diffusion in a slab dies away sideways over about its thickness), so it reaches less far
// into a heap than down through the column below a high sun: low on a heap, only the flanks facing
// the light glow, and the base beyond them sinks into its own shade. The key light is grazing
// below GRAZING.x and high above GRAZING.y (sines of ≈ 3° and 30°).
const OCTAVE_REACH = 0.35;
const GRAZING_OCTAVE_REACH = 0.5;
const GRAZING = vec2f(0.05, 0.5);
// The light a heap's crown catches per area of the column below it: all of a light overhead, but
// of a grazing one only what falls on the crown's sunward slopes; the rest falls on the flanks
// facing it, which blaze, and diffuses in from them (flankGlow).
const GRAZING_CROWN = 0.15;
// How far past a cloud's face diffused light behaves as if the cloud went on, in optical depth:
// two thirds of a transport mean free path, 2 / (3(1 − g)).
const EXTRAPOLATION = 2.0 / (3.0 * (1.0 - FORWARD));
// Beer–powder (Schneider 2015): light must scatter in a while before it can come back out, so
// sun-facing edges seen from the shadowed side are darker than Beer's law alone says.
const POWDER = 0.6;
// Share of the ambient that is skylight slipping in through the cloud's nearby sides. It is what
// tints shaded sides and bases blue in daylight, and it reaches only as far in as the shortest way
// out, toward the light or up through the column: edges take all of it, a broad heap's core little.
const SIDE_SKYLIGHT = 0.5;
const OPEN_SIDES = 0.15; // the share of it that even a core sees, through the heap's ragged sides
// Optical depth toward the key light over which a sample passes from the lit side of the cloud,
// which sees the whole sky, to the shaded side, which sees only the half turned from the light.
const SHADE_DEPTH = 8.0;

const DETAIL_WEIGHTS = vec3f(0.625, 0.25, 0.125);

// Typical spacing of the turrets and of the detail, km: their Worley fBm starts at 8 and at 4
// cells across a tile, with two finer octaves above each.
const TURRET_SPACING = SHAPE_TILE / 16.0;
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
// sky is cloud there, the height fraction its heaps' tops reach, and how far the wind shear has
// carried the heaps' shapes (km, horizontal), and how dense they still are.
struct Weather {
  cover: f32,
  top: f32,
  warp: vec2f,
  density: f32,
  spread: f32, // how far a deck has spread the heaps' domes out (0 free, 1 capped)
}

// Local coverage is the mood's mean, broken into fields and gaps. Heaps climb with it, from
// fair-weather puffs where it is thin to taller heaps where it is thick, and at the hearts of the
// weather's convection cells, where the air rises fastest, they tower as far as the mood allows.
// The weather's finer Worley shears the heaps' shapes by different amounts from place to place,
// stretching some into long rafts and bunching others, so each heap's outline is its own. A low
// deck (deck.wgsl) shades the ground that feeds the heaps' thermals and caps them under its
// inversion: as it closes in they stop towering, stay lower and spread out flat (stratocumulus
// cumulogenitus), their domes thinning gradually to their edges; a broken deck still has its heaps
// in the gaps, but fewer and thinner as it closes, and none are left by DECK_CAPS_HEAPS.
fn weatherAt(position: vec3f) -> Weather {
  let weather = sampleNoise(vec3f(position.xz, 0.5 * u.cloudEvolution) / WEATHER_TILE);
  let open = saturate(u.cloudCoverage + (weather.r - 0.5) * WEATHER_CONTRAST);
  var deckCover = u.deckCover;
  if (stormAbout()) {
    deckCover = deckCoverAt(position.xz + u.cloudWind);
  }
  let capped = saturate(deckCover / DECK_CAPS_HEAPS);
  let suppressed = capped * capped * capped;
  let cover = open * (1.0 - suppressed);
  let towering = u.cloudTowers * smoothstep(TOWER_CELLS.x, TOWER_CELLS.y, weather.g) * (1.0 - capped);
  let warp = WARP * (weather.ba - 0.5);
  let top = mix(mix(FAIR_TOPS.x, FAIR_TOPS.y, cover), 1.0, towering) * (1.0 - CAPPED_TOPS * capped);
  return Weather(cover, top, warp, 1.0 - suppressed, capped);
}

// A dome that the heaps' cores push up into (Schneider 2017's cumulus height gradient): the
// higher a heap's own field, the higher its top. Free heaps close over in a steep dome; those a
// deck has `spread` out thin away gradually from their cores to their edges.
fn heightProfile(h: f32, top: f32, spread: f32) -> f32 {
  let rise = h / top;
  return saturate(1.0 - mix(rise * rise * rise, pow(max(rise, 0.0), SPREAD_DOME), spread));
}

// The field below which no air has yet condensed: a level plane that cuts every heap's base flat
// and smooth, whatever the detail does to its flanks.
fn condensationField(h: f32) -> f32 {
  return CORE * h / BASE;
}

// How far past the threshold of cloud the field lies at a point: negative in clear air, and the
// cloud's core CORE past it. The heaps, shaped by height, form a continuous field; turrets bulge
// from it, and detail displaces it (wispy below, billowy above) before the sharp threshold turns
// it into cloud, so the detail carves the boundary itself, though never far from the heaps'.
// A sample standing for `footprint` km takes the mean of the features it cannot resolve, and the
// detail is not read where it could not carry the field across the threshold or into the core:
// there the air is clear, or the cloud whole, whatever the detail says.
fn cumulusField(p: vec3f, weather: Weather, footprint: f32) -> f32 {
  let h = heightFraction(p);
  let rise = h / weather.top;
  let profile = heightProfile(h, weather.top, weather.spread);
  let threshold = 1.0 - weather.cover;
  let crown = smoothstep(0.3, 0.8, rise);
  let attached = mix(ATTACHED.x, ATTACHED.y, crown);
  let turrets = TURRETS * resolved(TURRET_SPACING, footprint);
  let erosion = mix(EROSION.x, EROSION.y, crown) * resolved(DETAIL_SPACING, footprint);
  let detailReach = 0.5 * erosion; // the most the detail moves the field either way
  // The heaps never exceed their profile, so where even turrets and detail could not carry them
  // across the threshold the noise is not read.
  let base = condensationField(h);
  if (MAX_HEAPS * profile + attached <= threshold || base <= 0.0) {
    return min(MAX_HEAPS * profile - threshold, base);
  }
  let position = cloudSpace(p) + vec3f(weather.warp.x, 0.0, weather.warp.y);
  let shape = sampleNoise(position / SHAPE_TILE);
  let eroded = remap(shape.r, 0.5 * dot(shape.gba, DETAIL_WEIGHTS), 1.0, 0.0, 1.0);
  let heaps = max(remap(eroded, HEAPS_RANGE.x, HEAPS_RANGE.y, 0.0, 1.0), 0.0) * profile;
  // Broad turrets swell the flanks and tops and lobe the base's outline; the condensation level
  // still cuts it flat.
  let body = heaps + turrets * (shape.b - 0.5);
  let limit = min(heaps + attached - threshold, base);
  if (erosion <= 0.0 || min(body + detailReach - threshold, limit) <= 0.0 || body - detailReach >= threshold + CORE) {
    return min(body - threshold, limit);
  }
  let churn = vec3f(0.0, DETAIL_CHURN * u.cloudEvolution, 0.0);
  let detail = dot(sampleNoise((position + churn) / DETAIL_TILE).gba, DETAIL_WEIGHTS);
  let billows = mix(detail, 1.0 - detail, smoothstep(0.1, 0.4, rise));
  return min(body + erosion * (0.5 - billows) - threshold, limit);
}

// Density at the base relative to the body, at a point.
fn baseDensity(p: vec3f) -> f32 {
  return mix(BASE_DENSITY, 1.0, saturate(heightFraction(p) * 3.0));
}

// Density in [0, 1] from how far past the threshold the field lies: the rim, then the core, each
// reached over a ramp widened by `widening`.
fn fill(field: f32, widening: f32) -> f32 {
  return RIM * saturate(field / (BOUNDARY + widening)) + (1.0 - RIM) * saturate(field / (CORE + widening));
}

// Density in [0, 1] at a sample standing for `footprint` km. Across a long sample the field
// sweeps through the threshold's ramps and beyond, so its mean density rises gently rather than
// jumping as an edge crosses the sample: the ramps are widened by how far the field typically
// changes over the footprint. Where the light march and shadow map step far, heaps then shade
// smoothly as they drift instead of sparkling and flickering.
fn cumulusDensity(p: vec3f, weather: Weather, footprint: f32) -> f32 {
  return fill(cumulusField(p, weather, footprint), FIELD_CHANGE * footprint) * baseDensity(p) * weather.density;
}

// ∫ saturate(f / width) df: one ramp, integrated.
fn rampIntegral(field: f32, width: f32) -> f32 {
  let ramp = saturate(field / width);
  return width * 0.5 * ramp * ramp + max(field - width, 0.0);
}

// ∫ fill(f, 0) df.
fn fillIntegral(field: f32) -> f32 {
  return RIM * rampIntegral(field, BOUNDARY) + (1.0 - RIM) * rampIntegral(field, CORE);
}

// The mean density along a step over which the field runs linearly from `a` to `b`: the
// threshold, which a heap crosses in far less than a step, integrated exactly between two samples
// instead of taken at one.
fn meanCloud(a: f32, b: f32) -> f32 {
  if (abs(b - a) < 1e-4) {
    return fill(0.5 * (a + b), 0.0);
  }
  return (fillIntegral(b) - fillIntegral(a)) / (b - a);
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

// Optical depth of the column above a sample, up to its heap's top: the way skylight comes down
// into it, and, under a grazing light, the way light diffused through the sunlit crown comes down
// to the base. It is read from the heap's own field rather than marched: how far past the
// threshold the field lies at the sample (`field`, at height fraction `h`) says how strong the
// heap is there, and so, through the dome's profile, how high it reaches above, and how dense the
// column is on the way (Simpson's rule, with the density gone at the top). At a heap's thin edges
// the column is short and faint; under its strong cores, tall and dense.
fn opticalDepthAbove(h: f32, field: f32, weather: Weather) -> f32 {
  let threshold = 1.0 - weather.cover;
  let heaps = (max(field, 0.0) + threshold) / max(heightProfile(h, weather.top, weather.spread), 1e-3);
  let open = saturate(1.0 - threshold / max(heaps, 1e-4));
  let top = weather.top * mix(pow(open, 1.0 / 3.0), pow(open, 1.0 / SPREAD_DOME), weather.spread);
  let height = max(top - h, 0.0);
  let middle = h + 0.5 * height;
  let middleField = heaps * heightProfile(middle, weather.top, weather.spread) - threshold;
  let density = (fill(field, 0.0) + 4.0 * fill(middleField, 0.0)) / 6.0;
  return density * weather.density * height * (u.cloudTop - u.cloudBottom) * EXTINCTION * u.cloudDensity;
}

// How much diffuse light reaches a sample through cloud of optical depth τ, such as skylight down
// through the column above it and grass light up through its height over the base. Two-stream
// diffuse transmission, 1 / (1 + ¾(1 − g)τ) (Bohren 1987): edges see nearly all of it, a thick
// heap's core very little, which is what lets clouds read darker than the sky behind them.
fn diffuseTransmission(opticalDepth: vec2f) -> vec2f {
  return 1.0 / (1.0 + 0.75 * (1.0 - FORWARD) * opticalDepth);
}

// How much deeper each multiple-scattering octave reaches under the key light `light`.
fn octaveReachUnder(light: vec3f) -> f32 {
  return mix(GRAZING_OCTAVE_REACH, OCTAVE_REACH, smoothstep(GRAZING.x, GRAZING.y, light.y));
}

fn dropletPhase(cosTheta: f32, anisotropy: f32) -> f32 {
  return mix(henyeyGreenstein(cosTheta, FORWARD * anisotropy), henyeyGreenstein(cosTheta, BACKWARD * anisotropy), BACKWARD_WEIGHT);
}

// Direct light scattered toward the eye per unit illuminance, summed over bounces (Wrenninge et
// al. 2013, "Oz: The Great and Volumetric"): later octaves reach deeper with softer phases, so
// thick cloud glows white instead of turning grey. `shade` is the share of the light that reaches
// the sample past anything else in its way (x), and the share that reaches where its many-times
// scattered light comes from (y).
fn scattering(opticalDepth: f32, cosTheta: f32, octaveReach: f32, shade: vec2f) -> f32 {
  var result = 0.0;
  var energy = 1.0;
  var reach = 1.0;
  var anisotropy = 1.0;
  for (var octave = 0u; octave < OCTAVES; octave++) {
    let lit = select(shade.y, shade.x, octave == 0u);
    result += lit * energy * dropletPhase(cosTheta, anisotropy) * exp(-reach * opticalDepth);
    energy *= OCTAVE_ENERGY;
    reach *= octaveReach;
    anisotropy *= OCTAVE_SPREAD;
  }
  let powder = 1.0 - POWDER * exp(-2.0 * opticalDepth) * (0.5 - 0.5 * cosTheta);
  return result * powder;
}

// Light diffused down to a sample from its crown, per unit illuminance: what the crown catches of
// the key light (`catches`, and `shade`, the share of it past anything else in its way), carried
// down through the column above by diffusion, 1 / (1 + ¾(1 − g)τ) (Bohren 1987), which unlike the
// octaves' exponentials keeps a thick heap's base glowing faintly, and scattered toward the eye
// with the octaves' energies and phases (`phase`, their sum).
fn crownGlow(above: f32, catches: f32, shade: f32, phase: f32) -> f32 {
  return catches * shade * diffuseTransmission(vec2f(above)).x * phase;
}

// Light diffused in sideways from the sunlit flanks, per unit illuminance: the rest of a grazing
// light (`catches` falls on the crown), past anything else in its way (`shade`). Diffusing across
// a slab, it leaks out through the base and the top as it goes, so it dies away as the slab's
// fundamental mode, e^(−π x / (T + 2 z₀)) over optical depth x into a slab T deep (z₀ the
// extrapolation length): under the low crown of a flat heap within a few hundred metres, but deep
// into the base of a tall bank, which glows a dim gold far in from the flanks facing the sun.
fn flankGlow(toLight: f32, column: f32, catches: f32, shade: f32, phase: f32) -> f32 {
  return (1.0 - catches) * shade * exp(-PI * toLight / (column + 2.0 * EXTRAPOLATION)) * phase;
}

// The octaves' summed phase past the first, for crownGlow and flankGlow.
fn diffusedPhase(cosTheta: f32) -> f32 {
  var result = 0.0;
  var energy = 1.0;
  var anisotropy = 1.0;
  for (var octave = 1u; octave < OCTAVES; octave++) {
    energy *= OCTAVE_ENERGY;
    anisotropy *= OCTAVE_SPREAD;
    result += energy * dropletPhase(cosTheta, anisotropy);
  }
  return result;
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
  let octaveReach = octaveReachUnder(lighting.keyDirection);
  // What the crowns catch of the key light per area of the columns below them.
  let catches = mix(GRAZING_CROWN, 1.0, max(lighting.keyDirection.y, 0.0));
  let phase = diffusedPhase(cosTheta);

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
    let opticalDepth = meanCloud(before, field) * baseDensity(p) * weather.density * EXTINCTION * u.cloudDensity * span;
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
    let h = saturate(heightFraction(q));
    let lightJitter = fract(jitter + GOLDEN_RATIO * (lit - enter) / stepLength);
    let lightDepth = opticalDepthToLight(q, lighting.keyDirection, weather, lightJitter);
    // Beside a deck, the cells between the step and a low light may shade it (deck.wgsl), and the
    // light diffused many times comes down from the heap's crown, which may stand in the sun above
    // them: shaded flanks and bases still glow, lit ones blaze.
    var shade = vec2f(1.0);
    if (deckAbout()) {
      let crown = q * (1.0 + max(weather.top - h, 0.0) * (u.cloudTop - u.cloudBottom) / length(q));
      shade = vec2f(deckShade(q), deckShade(crown));
    }
    let above = opticalDepthAbove(h, mix(before, field, saturate((lit - t + span) / max(span, 1e-6))), weather);
    // Light diffused many times takes whichever way in brings more: along the light, or down from
    // the crown and in from the flanks.
    let below = extinction * h * (u.cloudTop - u.cloudBottom); // optical depth down to the base
    let diffused = crownGlow(above, catches, shade.y, phase) + flankGlow(lightDepth, above + below, catches, shade.x, phase);
    let direct = keyLight * max(scattering(lightDepth, cosTheta, octaveReach, shade), diffused);
    // Ambient: skylight from above and grass light from below, blended by height and each dimmed
    // by the cloud it diffuses through, plus skylight from the sides.
    let reach = diffuseTransmission(vec2f(above, below));
    let sky = mix(lighting.sky, lighting.shadedSky, 1.0 - exp(-lightDepth / SHADE_DEPTH));
    let side = sky * mix(diffuseTransmission(vec2f(min(lightDepth, above))).x, 1.0, OPEN_SIDES);
    let ambient = mix(mix(lighting.ground * reach.y, sky * reach.x, sqrt(h)), side, SIDE_SKYLIGHT);
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
