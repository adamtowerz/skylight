// The deck: a low grey layer of stratus and nimbostratus, the sky of a rainy day. Nearest of the
// cloud layers, it hides everything above it where it is whole. It is far too thick and even to
// march: the eye sees only its underside, lit by what diffuses down through it (decklight.wgsl),
// so it is a slab whose column varies across the sky, found where the view ray meets its base.
//
// As the weather brings it in (`weather.ts`) it covers more of the sky: first a broken
// stratocumulus, then an unbroken grey dome. Wind shear rolls the layer into long billows across
// the wind (undulatus), so a broken deck lies in rows along them, unevenly spaced, merging,
// splitting and breaking up as eddies push them about, its cells (the noise volume's
// Perlin–Worley, after Schneider 2015) drawn out along the rolls, lumpy, clumped in patches with
// blue or sunset between them, and thinning toward their edges, where finer wisps drawn out
// along the wind fray them. Its underside is never flat, even where whole: the rolls, cells and
// Worley lumps deepen and thin its column, darker where it is deeper and sags lower, lighter
// between. It drifts slowly, at the heaps' angular pace, so the cloud history follows it. Beneath it, where it is thick,
// ragged shreds of scud (fractus) hurry past, lower and so faster across the sky; lit only by the
// deck above and the dim grass below, they are darker than the deck.
//
// At sunset the deck can catch fire from below. From under the deck a sun just below the horizon
// shines upward, along a path that dips beneath the base and climbs back to its height a hundred
// kilometres off toward the sun: if the deck breaks there, the low red light floods in under it
// and lights its underside, most on the flanks of its rolls and lumps that face the sun, least
// in the lee of those that hang lower toward it. That is the deep orange underside of a Nordic
// sunset under clouds, gone within minutes as the sun sinks out of reach of the base.

// The deck's wind relative to the heaps': at about a third of their height, a third as fast, so
// it drifts across the sky at their angular pace; the scud beneath it hurries past faster still.
const DECK_SPEED = 0.35;
const SCUD_SPEED = 0.6;
// Rolls, the roll vortices of a sheared mixed layer (Atkinson & Zhang 1996): crest to crest, km,
// across the wind (unit, x = east, z = north); how far they wander (in rolls) over how many km.
const ROLL_SPACING = 0.8;
const ROLL_ACROSS = vec2f(0.93, -0.37);
const ROLL_BEND = 1.2;
const ROLL_BEND_TILE = 12.0;
// Nor are they even: eddies along each roll push it about by up to ROLL_WARP rolls over patches
// ROLL_WARP_TILE km (along, across), squeezing neighbours together here and parting them there,
// and the rolls fade and strengthen along their length over ROLL_FADE_TILE, so rows merge, split
// and break into cells.
const ROLL_WARP = 0.9;
const ROLL_WARP_TILE = vec2f(5.0, 2.0);
const ROLL_FADE_TILE = vec2f(7.0, 3.0);
// How many times longer than wide the cells are, drawn out along the rolls.
const ROLL_STRETCH = 1.6;
// Tiles of the noise volume, km: where the deck is broken or whole, its cells, and the lumps
// that fray their edges and mottle its base.
const DECK_PATCH_TILE = 40.0;
const DECK_CELL_TILE = 3.0;
const LUMP_TILE = 1.0;
// Typical spacing of the lumps, km (the Worley fBm's first octave has 4 cells per tile).
const LUMP_SPACING = LUMP_TILE / 4.0;
// Half the range of the deck's field over which its cover goes from none to nearly whole.
const FIELD_SPREAD = 0.3;
// Share of the deck's field that is its cells (the rest is its patches), and how far the rolls
// carry it: a broken deck breaks into rows of cells along the rolls, with lanes between them.
const DECK_CELLS = 0.8;
const ROLL_ROWS = 0.12;
// How far the lumps carry the edges of the cells, in units of the field; and wisps, finer and
// drawn out along the wind (tile, km, and stretch), that eat into them where they are thin.
const LUMP_EDGES = 0.35;
const DECK_WISP_TILE = 0.6;
const DECK_WISP_STRETCH = 4.0;
const DECK_WISP_SPACING = DECK_WISP_TILE / 8.0;
const DECK_WISP_DEPTH = 0.12;
// Past the edge of a gap a cell fades in over DECK_EDGE of the field, frayed and thin, and
// deepens over DECK_BODY, from HEART_EDGE of its depth to all of it at its heart: broken cells
// are greyest at their hearts. Its column grows as the cube of the way in (FRINGE), so it
// stays a thin veil a good way in, the optical depth of an edge grows gradually across it, and
// what it lets through, and diffracts, fades over a band rather than at a contour.
const DECK_EDGE = 0.3;
const FRINGE = 3.0;
const DECK_BODY = 0.35;
const HEART_EDGE = 0.25;
// How much deeper or shallower (±, a share of the mean) the rolls, the cells and the lumps make a
// whole deck's column: its base is mottled, darker where it is deep.
const ROLL_CONTRAST = 0.3;
const CELL_CONTRAST = 0.3;
const LUMP_CONTRAST = 0.5;
// The thinnest a whole deck gets, as a share of its mean column: thinner than that is the edge of
// a gap.
const THINNEST = 0.4;
// How far the base sags under a column one mean depth deeper than the mean, km.
const RELIEF = 0.12;
// Scud: how far beneath the base, km; the size of its shreds along and across the wind; how much
// of the sky it covers under a whole deck; its thickest optical depth, and over how much of its
// field it gets there.
const SCUD_BELOW = 0.25;
const SCUD_TILE = vec2f(3.0, 1.2);
const SCUD_COVER = 0.25;
const SCUD_DEPTH = 4.0;
const SCUD_EDGE = 0.12;
// A sun (or moon) lower than this (the sine of ≈ 3°) may light the deck from beneath, through a
// gap between these distances, km; the scud's ragged shreds face it as if they rose this steeply.
const UNDERLIGHT_BELOW = 0.05;
const UNDERLIGHT_REACH = vec2f(10.0, 150.0);
// How far along the gap the light's path takes to climb through the base, km; how far off the
// first of the sags it passes beneath lies, km (then twice as far, each time; the base's rise is
// taken to the second); and how deep into its path a sag hangs to take out all but 1/e of the
// light, km: a sag's fringe lets some through.
const UNDERLIGHT_CROSSING = 8.0;
const UNDERLIGHT_SHADE_STEP = 0.1;
const UNDERLIGHT_SHADE_SOFTNESS = 0.08;
// The share of the light the lee of a lump still gets, and how far a base that turns from the
// light still takes it in (as a cosine).
const UNDERLIGHT_LEE = 0.4;
const UNDERLIGHT_FRINGE = 0.06;
const SCUD_FLANK = 0.3;
// The deck's cells' tops, for the shade they cast on the heaps beside them: the tallest stand
// this many times the deck's thickness above its base; the light's path past them is sampled at
// these shares of the way to where it clears them (at least, and at most, DECK_SHADE_REACH km),
// and a top this far above or below the path (km) shades it fully or not at all. Their shadows'
// penumbrae widen by DECK_PENUMBRA km per km from the cell (light diffused through and around a
// cell, not the sun's disc alone), and the deck's field changes by about DECK_FIELD_SLOPE per km
// across a cell's edge.
const DECK_TALLEST = 1.3;
const DECK_SHADE_REACH = vec2f(1.0, 40.0);
const DECK_SHADE_SAMPLES = array(0.1, 0.35, 0.8);
const DECK_SHADE_SOFTNESS = 0.35;
const DECK_PENUMBRA = 0.05;
const DECK_FIELD_SLOPE = 1.0;
// Rain's extinction, km⁻¹ at 1 mm/h, and how it grows with the rate: the Marshall–Palmer drops'
// cross-section, less the half they only diffract forward (Atlas 1953).
const RAIN_EXTINCTION = 0.18;
const RAIN_EXTINCTION_GROWTH = 0.63;

// Where a planet-centred position sits in the deck's drifting field (km), at a wind `speed`
// relative to the heaps'.
fn deckSpace(p: vec3f, speed: f32) -> vec2f {
  return p.xz - speed * u.cloudWind;
}

// The deck's field at `x` (deck space) before its lumps: its patches, its cells drawn out along
// the rolls, and the rows the rolls gather them into (x); the rolls (y) and the cells (z) alone.
fn deckRows(x: vec2f) -> vec3f {
  let evolution = 0.3 * u.cloudEvolution;
  let across = dot(x, ROLL_ACROSS);
  let along = dot(x, vec2f(-ROLL_ACROSS.y, ROLL_ACROSS.x));
  let bend = ROLL_BEND * sampleNoise(vec3f(x / ROLL_BEND_TILE, 0.37)).r;
  let eddies = sampleNoise(vec3f(vec2f(along, across) / ROLL_WARP_TILE, 0.61)).r;
  let strength = smoothstep(0.25, 0.75, sampleNoise(vec3f(vec2f(along, across) / ROLL_FADE_TILE, 0.83)).r);
  let rolls = cos(TAU * (across / ROLL_SPACING + bend + ROLL_WARP * eddies));
  let drawn = vec2f(across, along / ROLL_STRETCH);
  let patches = sampleNoise(vec3f(x / DECK_PATCH_TILE, evolution / DECK_PATCH_TILE)).r;
  let cells = sampleNoise(vec3f(drawn / DECK_CELL_TILE, evolution / DECK_CELL_TILE));
  return vec3f(mix(patches, 0.5 * (cells.r + cells.g), DECK_CELLS) + ROLL_ROWS * mix(0.2, 1.6, strength) * rolls, rolls, cells.g);
}

// The field past which the deck is cloud. The field gathers about ½, so the cover is spread over
// its middle (FIELD_SPREAD), and the last gaps close as the cover nears 1: the deck covers about
// u.deckCover of the sky, and all of it at 1. Its fringes start a quarter of the way out across
// their veil, so that they still fill about as much sky as they hide.
fn deckThreshold() -> f32 {
  return mix(0.5 + FIELD_SPREAD, 0.5 - FIELD_SPREAD, u.deckCover) - smoothstep(0.8, 1.0, u.deckCover) - 0.25 * DECK_EDGE;
}

// The deck's column at `x` (deck space), as a share of its mean depth where whole: 0 in its gaps,
// thinning toward their edges, rolled, celled and lumped by as much as a sample standing for
// `footprint` km resolves (x); and the column it thins from, the depth of the cell at its heart (y).
fn deckColumn(x: vec2f, footprint: f32) -> vec2f {
  let evolution = 0.3 * u.cloudEvolution;
  let across = dot(x, ROLL_ACROSS);
  let along = dot(x, vec2f(-ROLL_ACROSS.y, ROLL_ACROSS.x));
  let rows = deckRows(x);
  let detail = resolved(LUMP_SPACING, footprint);
  let lumps = (dot(sampleNoise(vec3f(x / LUMP_TILE, evolution / LUMP_TILE)).gba, DETAIL_WEIGHTS) - 0.5) * detail;
  let field = rows.x + LUMP_EDGES * lumps;
  let threshold = deckThreshold();
  let body = saturate((field - threshold) / DECK_BODY);
  let wisps = sampleNoise(vec3f(vec2f(across, along / DECK_WISP_STRETCH) / DECK_WISP_TILE, evolution / DECK_WISP_TILE)).b - 0.5;
  let past = field - threshold - DECK_WISP_DEPTH * (1.0 - body) * wisps * resolved(DECK_WISP_SPACING, footprint);
  if (past <= 0.0) {
    return vec2f(0.0);
  }
  let mottle = ROLL_CONTRAST * rows.y + CELL_CONTRAST * 2.0 * (rows.z - 0.5) + LUMP_CONTRAST * 2.0 * lumps;
  let heart = max(mix(HEART_EDGE, 1.0, saturate(past / DECK_BODY)) * (1.0 + mottle), THINNEST * body);
  return vec2f(pow(saturate(past / DECK_EDGE), FRINGE) * heart, heart);
}

// How far the base lies below its mean height, km: it sags where the column is deep.
fn sag(column: f32) -> f32 {
  return RELIEF * (column - 1.0);
}

// Optical depth of the deck above the planet-centred point `p` on its base.
fn deckDepthAt(p: vec3f, footprint: f32) -> f32 {
  return u.deckDepth * deckColumn(deckSpace(p, DECK_SPEED), footprint).x;
}

// How much of the key light reaches the planet-centred point `p` past the deck's cells, which
// stand as tall above its base as they are deep: a heap beside the deck, its base among the
// cells' tops, is shaded by those between it and a low light, and lit through the gaps. A cell's
// shadow is soft, with a penumbra that widens with the way from the cell to the heap: not the
// sun's 0.53° disc but the much wider spread of light diffused through the cell's thin edges and
// scattered in around them. So each cell is taken as blurred over that width, its field's edge
// and its top's height softened alike, which also leaves out its lumps and wisps.
fn deckShade(p: vec3f) -> f32 {
  let key = keyLight();
  let height = length(p) - u.bottomRadius;
  let across = max(length(key.direction.xz), 1e-3);
  let toward = key.direction.xz / across;
  let climb = key.direction.y / across;
  let tallest = u.deckBase + DECK_THICKNESS * DECK_TALLEST;
  if (height >= tallest) {
    return 1.0;
  }
  let reach = clamp((tallest - height) / max(climb, 1e-3), DECK_SHADE_REACH.x, DECK_SHADE_REACH.y);
  let x = deckSpace(p, DECK_SPEED);
  let threshold = deckThreshold();
  var lit = 1.0;
  for (var i = 0; i < 3; i++) {
    let d = reach * DECK_SHADE_SAMPLES[i];
    let ray = height + (climb + 0.5 * d / u.bottomRadius) * d;
    let penumbra = DECK_PENUMBRA * d;
    let blur = DECK_FIELD_SLOPE * penumbra;
    let rows = deckRows(x + toward * d);
    let past = rows.x - threshold;
    let mottle = ROLL_CONTRAST * rows.y + CELL_CONTRAST * 2.0 * (rows.z - 0.5);
    let heart = mix(HEART_EDGE, 1.0, saturate(past / (DECK_BODY + blur))) * (1.0 + mottle);
    let column = smoothstep(-0.5 * blur, DECK_EDGE + 0.5 * blur, past) * heart;
    let softness = DECK_SHADE_SOFTNESS + penumbra;
    lit *= 1.0 - smoothstep(-softness, softness, u.deckBase + DECK_THICKNESS * column - ray);
  }
  return lit;
}

// How much of a key light low enough to shine up under the deck gets in, from `x` (deck space):
// through the gap where its path climbs back to the base's height. The path climbs so gently that
// it rises through the base over many kilometres, so the gap is the deck's openness along that
// stretch of it, not at a point: the share of it that is open, as what gets through is the mean
// of what each part of the sun's light finds, not what the stretch's mean column would let by.
fn underlightGap(x: vec2f) -> f32 {
  let key = keyLight();
  let across = max(length(key.direction.xz), 1e-3);
  let toward = key.direction.xz / across;
  // A path dipping at elevation −e from the base climbs back to its height 2R tan e away.
  let dip = max(-key.direction.y, 0.0) / across;
  let gap = x + toward * clamp(2.0 * u.bottomRadius * dip, UNDERLIGHT_REACH.x, UNDERLIGHT_REACH.y);
  let near = deckColumn(gap - 0.5 * UNDERLIGHT_CROSSING * toward, 1.0).x;
  let far = deckColumn(gap + 0.5 * UNDERLIGHT_CROSSING * toward, 1.0).x;
  return 1.0 - 0.5 * (saturate(near / THINNEST) + saturate(far / THINNEST));
}

// How much of the low key light that gets in under the deck reaches its base at `x` (deck space),
// of column `column`, past the sags of the base between it and the light (x): a lump that hangs
// lower toward the light shades the base behind it, so the underside is lit on the flanks and
// fronts of its lumps and rolls that face the light and dims in their lee, lumpy rather than an
// even wash. The lee is never dark: the lit lumps share their light into it as it diffuses
// through them (radiative smoothing, as in decklight.wgsl). And how far the base there rises
// toward the light over its lumps, km per km (y).
fn underlightReach(x: vec2f, column: f32, footprint: f32) -> vec2f {
  let key = keyLight();
  let across = max(length(key.direction.xz), 1e-3);
  let toward = key.direction.xz / across;
  let climb = key.direction.y / across;
  let here = sag(column);
  var hangs = 0.0;
  var rise = 0.0;
  for (var i = 0; i < 4; i++) {
    let d = UNDERLIGHT_SHADE_STEP * exp2(f32(i));
    let there = sag(deckColumn(x + toward * d, max(footprint, 0.25 * d)).x);
    if (i == 1) {
      rise = (here - there) / d;
    }
    hangs = max(hangs, there - here + climb * d);
  }
  return vec2f(mix(UNDERLIGHT_LEE, 1.0, exp(-hangs / UNDERLIGHT_SHADE_SOFTNESS)), rise);
}

// Radiance that cloud at the planet-centred point `q`, of optical depth `tau`, reflects down from
// a low key light shining up under the deck, of which `reach` arrives, onto the cloud as far as it
// faces the light, which is more where it `rises` toward the light (km per km), reflected by the
// slab above, fading in as the light sinks below UNDERLIGHT_BELOW. The base is no hard surface but a fringe where the droplets thin out, and the light
// skimming through it scatters some down wherever it faces (UNDERLIGHT_FRINGE).
fn underlight(q: vec3f, tau: f32, rise: f32, reach: f32) -> vec3f {
  let key = keyLight();
  let across = max(length(key.direction.xz), 1e-3);
  let facing = max(rise * across - key.direction.y, 0.0) / sqrt(1.0 + rise * rise) + UNDERLIGHT_FRINGE;
  if (reach <= 0.0) {
    return vec3f(0.0);
  }
  let sinking = smoothstep(UNDERLIGHT_BELOW, 0.0, key.direction.y);
  let irradiance = key.illuminance * transmittanceAt(q, key.direction) * facing * reach * sinking;
  return irradiance * slabReflectance(tau, max(facing, 0.01)) / PI;
}

// rgb: radiance toward the eye; a: transmittance of what lies beyond: the deck, the scud beneath
// it and the rain between them and the eye, seen through the air.
fn deck(dir: vec3f, lighting: CloudLighting) -> vec4f {
  if (u.deckCover <= 0.0 && u.rainRate <= 0.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let footprint = u.cloudCell * 2.0 * u.tanHalfFov.y / u.resolution.y;
  let hit = onLayer(dir, u.deckBase);
  let x = deckSpace(hit.xyz, DECK_SPEED);
  let column = deckColumn(x, hit.w * footprint);
  let mu = max(dir.y, DECK_VIEW_GRAZING);
  let lowLight = keyLight().direction.y < UNDERLIGHT_BELOW;
  var layer = vec4f(0.0, 0.0, 0.0, 1.0);
  if (column.x > 0.0) {
    let tau = u.deckDepth * column.x;
    let body = max(tau, u.deckDepth * column.y);
    layer = deckVeil(dir, hit.xyz, tau, body, lighting.sky);
    if (lowLight) {
      // A thin edge is a veil of the light its cell catches from beneath, as it is of the rest:
      // the low light shines through it, neither shaded by the sags around it nor turned by its
      // slope, so it takes about the light of a level base.
      let gap = underlightGap(x);
      if (gap > 0.0) {
        let seen = veiled(tau, body, mu);
        let reach = underlightReach(x, column.x, hit.w * footprint);
        let lit = underlight(hit.xyz, body, seen * reach.y, gap * mix(1.0, reach.x, seen));
        layer += vec4f(seen * lit, 0.0);
      }
    }
  }
  // The light under the deck, on average: what shines on the scud from above, and on the rain.
  let deckMean = deckGlow(vec3f(0.0, 1.0, 0.0), hit.xyz, u.deckDepth, lighting.sky);
  let under = mix(lighting.sky, deckMean.rgb + deckMean.a * lighting.sky, u.deckCover);

  // Scud: thin, so lit as a slab by the light under the deck above it and the grass below.
  let scudCover = SCUD_COVER * smoothstep(0.6, 1.0, u.deckCover);
  if (scudCover > 0.0) {
    let low = onLayer(dir, u.deckBase - SCUD_BELOW);
    let along = deckSpace(low.xyz, SCUD_SPEED);
    let s = vec2f(dot(along, ROLL_ACROSS), dot(along, vec2f(-ROLL_ACROSS.y, ROLL_ACROSS.x)));
    let shreds = sampleNoise(vec3f(s / SCUD_TILE, 0.8 * u.cloudEvolution));
    let ragged = shreds.r - 0.5 * shreds.g * resolved(SCUD_TILE.y / 8.0, low.w * footprint);
    let tauScud = SCUD_DEPTH * saturate((ragged - (1.0 - scudCover)) / SCUD_EDGE);
    if (tauScud > 0.0) {
      let reflected = slabReflectance(tauScud, 0.5);
      var scud = under * (max(1.0 - reflected - exp(-2.0 * tauScud), 0.0) + u.groundAlbedo * reflected);
      if (lowLight) {
        scud += underlight(low.xyz, tauScud, SCUD_FLANK, underlightGap(deckSpace(low.xyz, DECK_SPEED)));
      }
      let through = exp(-tauScud / mu);
      layer = vec4f(scud + through * layer.rgb, through * layer.a);
    }
  }

  // Rain between the deck and the eye veils it a little with the light under the deck.
  if (u.rainRate > 0.0) {
    let rain = exp(-RAIN_EXTINCTION * pow(u.rainRate, RAIN_EXTINCTION_GROWTH) * (u.deckBase - SCUD_BELOW) / mu);
    layer = vec4f(mix(under, layer.rgb, rain), rain * layer.a);
  }
  return throughAir(layer, dir, hit.w);
}
