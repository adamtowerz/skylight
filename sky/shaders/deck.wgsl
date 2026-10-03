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
//
// A thunderstorm (storm.wgsl) rides in on the deck: under its core the base is a nimbostratus
// many times deeper, so far darker, and no calm sheet of rolls but ragged and lumpy, churning with
// its updraughts and downdraughts, its leading edge a shelf lying in tiers along the gust front.
// Torn scud races beneath it, lit from the sides by the light under the thinner deck around the
// storm, so it shows paler against the dark base where that light still reaches it through the
// rain: most at the storm's edges. The downpour veils it all in the light under the deck, in
// curtains, heavier here and lighter there.

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
// taken to the second, and under a storm's deck also to UNDERLIGHT_RISE_STEP); and how deep
// into its path a sag hangs to take out all but 1/e of the light, km: a sag's fringe lets some
// through.
const UNDERLIGHT_CROSSING = 8.0;
const UNDERLIGHT_SHADE_STEP = 0.1;
const UNDERLIGHT_SHADE_SOFTNESS = 0.08;
const UNDERLIGHT_RISE_STEP = 0.04;
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
// cross-section, less the half they only diffract forward (Atlas 1953). A downpour of 45 mm/h
// takes out about 2 km⁻¹: the far side of a storm is lost a couple of kilometres off.
const RAIN_EXTINCTION = 0.18;
const RAIN_EXTINCTION_GROWTH = 0.63;
// A storm's base: how much faster than the deck's it churns through the noise volume, the size of
// its billows (km), and how far they deepen and thin its column (±, a share of the mean). How far
// the shelf's tiers along the gust front deepen and thin it.
const STORM_CHURN = 10.0;
const STORM_BILLOW_TILE = 1.5;
const STORM_BILLOW_SPACING = STORM_BILLOW_TILE / 4.0;
const STORM_CONTRAST = 0.7;
// Finer, its heavier lobes, sagging pouches of the downdraughts (tile km, so about a quarter of
// it apart, and how much deeper they make it), and the thin wisps the updraughts tear out between
// them, drawn out along the wind (tile km, stretch, and how much thinner they leave it).
const STORM_LOBE_TILE = 0.5;
const STORM_LOBE_SPACING = STORM_LOBE_TILE / 4.0;
const STORM_LOBES = 0.9;
const STORM_WISP_TILE = 0.35;
const STORM_WISP_STRETCH = 3.0;
const STORM_WISP_SPACING = STORM_WISP_TILE / 8.0;
const STORM_WISPS = 0.6;
const SHELF_TIERS = 0.6;
// The storm's scud: hanging at this share of the way down from the base, faster than the deck's,
// and how much of the sky it covers under the storm's heart; its shreds' size along and across
// the wind, km.
const STORM_SCUD_BELOW = 0.4;
const STORM_SCUD_SPEED = 1.2;
const STORM_SCUD_COVER = 0.5;
const STORM_SCUD_TILE = vec2f(2.0, 0.6);
// The clearer air under a storm's deck, between its showers, takes out this much, km⁻¹ (a
// visibility of about 20 km); the way a low light skims beneath it from its edge is taken as
// running upwind at least this steeply, and its rain sampled no further out than this, km.
const UNDER_DECK_AIR = 0.2;
const STORM_SKIM = 0.2;
const STORM_SKIM_REACH = 4.0;
// How far off the light under the deck comes in from the sides, km, and the share of it that does.
const SIDELIGHT_REACH = 2.0;
const SIDELIGHT = 0.5;
// Rain falls in curtains a kilometre or so across (km), heavier and lighter than its mean by up to
// this share.
const CURTAIN_TILE = 1.5;
const CURTAIN_CONTRAST = 0.7;

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
// `cover` of the sky, and all of it at 1. Its fringes start a quarter of the way out across
// their veil, so that they still fill about as much sky as they hide.
fn deckThreshold(cover: f32) -> f32 {
  return mix(0.5 + FIELD_SPREAD, 0.5 - FIELD_SPREAD, cover) - smoothstep(0.8, 1.0, cover) - 0.25 * DECK_EDGE;
}

// How far a storm's base over `ground` (at `x`, deck space, where the rolls there are `rolls`)
// deepens and thins its column, as a share of its mean: billows boiling through it, heavy lobes
// hanging from it and wisps torn thin between them, and the tiers of the shelf at its leading
// edge, as much as a sample standing for `footprint` km resolves.
fn stormMottle(ground: vec2f, x: vec2f, rolls: f32, footprint: f32) -> f32 {
  let core = stormCoreAt(ground);
  if (core <= 0.0) {
    return 0.0;
  }
  let churn = STORM_CHURN * u.cloudEvolution;
  let billows = sampleNoise(vec3f(x / STORM_BILLOW_TILE, churn / STORM_BILLOW_TILE));
  let ragged = billows.r - 0.5 + (dot(billows.gba, DETAIL_WEIGHTS) - 0.5) * resolved(STORM_BILLOW_SPACING, footprint);
  let lobe = sampleNoise(vec3f(x / STORM_LOBE_TILE, churn / STORM_LOBE_TILE)).g;
  let lobes = smoothstep(0.35, 0.95, lobe) * resolved(STORM_LOBE_SPACING, footprint);
  let along = vec2f(dot(x, STORM_HEADING), dot(x, vec2f(-STORM_HEADING.y, STORM_HEADING.x)) * STORM_WISP_STRETCH);
  let wisp = sampleNoise(vec3f(along / (STORM_WISP_TILE * STORM_WISP_STRETCH), churn / STORM_WISP_TILE)).b;
  let wisps = smoothstep(0.5, 0.85, wisp) * (1.0 - lobes) * resolved(STORM_WISP_SPACING, footprint);
  let lead = smoothstep(u.stormCore.x, u.stormCore.y, upwind(ground));
  let shelf = 4.0 * lead * (1.0 - lead);
  return core * (STORM_CONTRAST * 2.0 * ragged + STORM_LOBES * lobes - STORM_WISPS * wisps)
    + u.stormPeak * shelf * SHELF_TIERS * rolls;
}

// The deck's column over `ground` (km east and north of the eye), as a share of its mean depth
// where whole: 0 in its gaps, thinning toward their edges, rolled, celled and lumped by as much as
// a sample standing for `footprint` km resolves (x); and the column it thins from, the depth of
// the cell at its heart (y).
fn deckColumn(ground: vec2f, footprint: f32) -> vec2f {
  let x = ground - DECK_SPEED * u.cloudWind;
  let evolution = 0.3 * u.cloudEvolution;
  let across = dot(x, ROLL_ACROSS);
  let along = dot(x, vec2f(-ROLL_ACROSS.y, ROLL_ACROSS.x));
  let rows = deckRows(x);
  let detail = resolved(LUMP_SPACING, footprint);
  let lumps = (dot(sampleNoise(vec3f(x / LUMP_TILE, evolution / LUMP_TILE)).gba, DETAIL_WEIGHTS) - 0.5) * detail;
  let field = rows.x + LUMP_EDGES * lumps;
  let threshold = deckThreshold(deckCoverAt(ground));
  let body = saturate((field - threshold) / DECK_BODY);
  let wisps = sampleNoise(vec3f(vec2f(across, along / DECK_WISP_STRETCH) / DECK_WISP_TILE, evolution / DECK_WISP_TILE)).b - 0.5;
  let past = field - threshold - DECK_WISP_DEPTH * (1.0 - body) * wisps * resolved(DECK_WISP_SPACING, footprint);
  if (past <= 0.0) {
    return vec2f(0.0);
  }
  let mottle = ROLL_CONTRAST * rows.y + CELL_CONTRAST * 2.0 * (rows.z - 0.5) + LUMP_CONTRAST * 2.0 * lumps
    + stormMottle(ground, x, rows.y, footprint);
  let heart = max(mix(HEART_EDGE, 1.0, saturate(past / DECK_BODY)) * (1.0 + mottle), THINNEST * body);
  return vec2f(pow(saturate(past / DECK_EDGE), FRINGE) * heart, heart);
}

// How far the base lies below its mean height, km: it sags where the column is deep.
fn sag(column: f32) -> f32 {
  return RELIEF * (column - 1.0);
}

// Optical depth of the deck above the planet-centred point `p` on its base.
fn deckDepthAt(p: vec3f, footprint: f32) -> f32 {
  return deckDepthOver(p.xz) * deckColumn(p.xz, footprint).x;
}

// How much of the key light reaches the planet-centred point `p` past the deck's cells, which
// stand as tall above its base as they are deep: a heap beside the deck, its base among the
// cells' tops, is shaded by those between it and a low light, and lit through the gaps. A cell's
// shadow is soft, with a penumbra that widens with the way from the cell to the heap: not the
// sun's 0.53° disc but the much wider spread of light diffused through the cell's thin edges and
// scattered in around them. So each cell is taken as blurred over that width, its field's edge
// and its top's height softened alike, which also leaves out its lumps and wisps.
// Its cover is the weather's own: near a storm, whose deck caps every heap, none are left to shade.
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
  let threshold = deckThreshold(u.deckCover);
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

// How much of a key light low enough to shine up under the deck gets in, from over `ground`:
// through the gap where its path climbs back to the base's height. The path climbs so gently that
// it rises through the base over many kilometres, so the gap is the deck's openness along that
// stretch of it, not at a point: the share of it that is open, as what gets through is the mean
// of what each part of the sun's light finds, not what the stretch's mean column would let by.
fn underlightGap(ground: vec2f) -> f32 {
  let key = keyLight();
  let across = max(length(key.direction.xz), 1e-3);
  let toward = key.direction.xz / across;
  // A path dipping at elevation −e from the base climbs back to its height 2R tan e away.
  let dip = max(-key.direction.y, 0.0) / across;
  let gap = ground + toward * clamp(2.0 * u.bottomRadius * dip, UNDERLIGHT_REACH.x, UNDERLIGHT_REACH.y);
  let near = deckColumn(gap - 0.5 * UNDERLIGHT_CROSSING * toward, 1.0).x;
  let far = deckColumn(gap + 0.5 * UNDERLIGHT_CROSSING * toward, 1.0).x;
  return (1.0 - 0.5 * (saturate(near / THINNEST) + saturate(far / THINNEST))) * underStorm(ground, toward);
}

// How much of a low light that gets in under a storm's deck where it ends survives the way from
// that edge to `ground`, coming from `toward` (unit, horizontal): it skims beneath the deck the
// whole way, through the moist air and the rain trailing from it. So as a storm moves off and the
// sky clears behind it, its underside does not catch fire all at once but from the clearing edge,
// the light sweeping in under it as the edge comes nearer.
fn underStorm(ground: vec2f, toward: vec2f) -> f32 {
  if (!stormAbout()) {
    return 1.0;
  }
  // How fast the way toward the light runs upwind, and so which of the deck's edges it meets.
  let climb = -dot(toward, STORM_HEADING);
  let here = upwind(ground);
  let edge = select(0.5 * (u.stormDeck.x + u.stormDeck.y), 0.5 * (u.stormDeck.z + u.stormDeck.w), climb > 0.0);
  let way = max((edge - here) / select(min(climb, -STORM_SKIM), max(climb, STORM_SKIM), climb > 0.0), 0.0);
  let between = ground + 0.5 * min(way, STORM_SKIM_REACH) * toward;
  return exp(-(UNDER_DECK_AIR + rainExtinction(rainOver(between))) * way);
}

// How much of the low key light that gets in under the deck reaches its base over `ground`,
// of column `column`, past the sags of the base between it and the light (x): a lump that hangs
// lower toward the light shades the base behind it, so the underside is lit on the flanks and
// fronts of its lumps and rolls that face the light and dims in their lee, lumpy rather than an
// even wash. The lee is never dark: the lit lumps share their light into it as it diffuses
// through them (radiative smoothing, as in decklight.wgsl). And how far the base there rises
// toward the light over its lumps, km per km (y).
fn underlightReach(ground: vec2f, column: f32, footprint: f32) -> vec2f {
  let key = keyLight();
  let across = max(length(key.direction.xz), 1e-3);
  let toward = key.direction.xz / across;
  let climb = key.direction.y / across;
  let here = sag(column);
  var hangs = 0.0;
  var rise = 0.0;
  for (var i = 0; i < 4; i++) {
    let d = UNDERLIGHT_SHADE_STEP * exp2(f32(i));
    let there = sag(deckColumn(ground + toward * d, max(footprint, 0.25 * d)).x);
    if (i == 1) {
      rise = (here - there) / d;
    }
    hangs = max(hangs, there - here + climb * d);
  }
  // A storm's deck, churned by its outflow, is lumped and lobed finer than that step resolves:
  // half its slope is taken over the finest, so their flanks catch the light within the broader
  // undulations.
  let stormy = stormDeckAt(ground);
  if (stormy > 0.0) {
    let fine = UNDERLIGHT_RISE_STEP;
    let lobed = (here - sag(deckColumn(ground + toward * fine, max(footprint, 0.25 * fine)).x)) / fine;
    rise = mix(rise, lobed, 0.5 * stormy);
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

// The light under the deck about `ground` (planet-centred `base` on the base above it), on
// average: what shines on the scud from above, and on the rain. Under a storm's core it is the dim
// light through the core, and the brighter light from under the thinner deck around it, coming in
// sideways through the rain: most at the storm's edges, all but lost in the heart of a downpour.
fn lightUnder(ground: vec2f, base: vec3f, sky: vec3f) -> vec3f {
  let up = vec3f(0.0, 1.0, 0.0);
  let depth = deckDepthOver(ground);
  let glow = deckGlow(up, base, depth, sky);
  let here = mix(sky, glow.rgb + glow.a * sky, deckCoverAt(ground));
  if (!stormAbout()) {
    return here;
  }
  // Around the storm the deck lets through more, as its diffuse transmission (slab.wgsl) does.
  let through = exp(-rainExtinction(rainOver(ground)) * SIDELIGHT_REACH);
  let diffused = 1.0 - slabReflectance(depth, 0.5);
  var sides = 0.0;
  for (var i = 0; i < 2; i++) {
    let side = ground + (f32(i) * 2.0 - 1.0) * SIDELIGHT_REACH * STORM_HEADING;
    sides += 0.5 * (1.0 - slabReflectance(deckDepthOver(side), 0.5)) / diffused;
  }
  return here * mix(1.0, sides, SIDELIGHT * through);
}

// Rain's extinction at `rate` mm/h, km⁻¹.
fn rainExtinction(rate: f32) -> f32 {
  return RAIN_EXTINCTION * pow(max(rate, 0.0), RAIN_EXTINCTION_GROWTH);
}

// Scud on the layer `below` km beneath the deck's base along `dir`, drifting at `speed`, its
// shreds `tile` km, covering about `cover` of the sky: thin, so lit as a slab by `under`, the
// light under the deck above it, and the grass below, and from beneath by a low light that gets
// in. In front of `layer` (the deck seen past it).
fn scud(dir: vec3f, layer: vec4f, below: f32, speed: f32, tile: vec2f, cover: f32, under: vec3f, footprint: f32) -> vec4f {
  let low = onLayer(dir, u.deckBase - below);
  let along = deckSpace(low.xyz, speed);
  let s = vec2f(dot(along, ROLL_ACROSS), dot(along, vec2f(-ROLL_ACROSS.y, ROLL_ACROSS.x)));
  let shreds = sampleNoise(vec3f(s / tile, 0.8 * u.cloudEvolution * speed / SCUD_SPEED));
  let ragged = shreds.r - 0.5 * shreds.g * resolved(tile.y / 8.0, low.w * footprint);
  let tau = SCUD_DEPTH * saturate((ragged - (1.0 - cover)) / SCUD_EDGE);
  if (tau <= 0.0) {
    return layer;
  }
  let reflected = slabReflectance(tau, 0.5);
  var lit = under * (max(1.0 - reflected - exp(-2.0 * tau), 0.0) + u.groundAlbedo * reflected);
  if (keyLight().direction.y < UNDERLIGHT_BELOW) {
    lit += underlight(low.xyz, tau, SCUD_FLANK, underlightGap(low.xz));
  }
  let through = exp(-tau / max(dir.y, DECK_VIEW_GRAZING));
  return vec4f(lit + through * layer.rgb, through * layer.a);
}

// rgb: radiance toward the eye; a: transmittance of what lies beyond: the deck, the scud beneath
// it and the rain between them and the eye, seen through the air.
fn deck(dir: vec3f, lighting: CloudLighting) -> vec4f {
  if (!deckAbout() && u.rainRate <= 0.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let footprint = u.cloudCell * 2.0 * u.tanHalfFov.y / u.resolution.y;
  let hit = onLayer(dir, u.deckBase);
  let ground = hit.xz;
  let column = deckColumn(ground, hit.w * footprint);
  let mu = max(dir.y, DECK_VIEW_GRAZING);
  let lowLight = keyLight().direction.y < UNDERLIGHT_BELOW;
  var layer = vec4f(0.0, 0.0, 0.0, 1.0);
  if (column.x > 0.0) {
    let depth = deckDepthOver(ground);
    let tau = depth * column.x;
    let body = max(tau, depth * column.y);
    layer = deckVeil(dir, hit.xyz, tau, body, lighting.sky);
    if (lowLight) {
      // A thin edge is a veil of the light its cell catches from beneath, as it is of the rest:
      // the low light shines through it, neither shaded by the sags around it nor turned by its
      // slope, so it takes about the light of a level base.
      let gap = underlightGap(ground);
      if (gap > 0.0) {
        let seen = veiled(tau, body, mu);
        let reach = underlightReach(ground, column.x, hit.w * footprint);
        let lit = underlight(hit.xyz, body, seen * reach.y, gap * mix(1.0, reach.x, seen));
        layer += vec4f(seen * lit, 0.0);
      }
    }
  }

  // The light under the deck, taken about halfway out along the view, where the scud and the rain
  // the eye sees through lie on average.
  let between = 0.5 * ground;
  let under = lightUnder(between, hit.xyz, lighting.sky);
  // The deck's scud, then the storm's beneath it.
  for (var i = 0; i < 2; i++) {
    let storming = i == 1;
    var cover = SCUD_COVER * smoothstep(0.6, 1.0, deckCoverAt(ground));
    if (storming) {
      cover = select(0.0, STORM_SCUD_COVER * stormCoreAt(ground), stormAbout());
    }
    if (cover > 0.0) {
      let below = select(SCUD_BELOW, STORM_SCUD_BELOW * u.deckBase, storming);
      let speed = select(SCUD_SPEED, STORM_SCUD_SPEED, storming);
      let tile = select(SCUD_TILE, STORM_SCUD_TILE, storming);
      layer = scud(dir, layer, below, speed, tile, cover, under, footprint);
    }
  }

  // Rain between the deck and the eye veils it with the light under the deck, as heavily as it
  // falls about halfway out along the view, and in curtains under a storm.
  var rate = rainOver(between);
  if (rate > 0.0) {
    let core = stormCoreAt(between) / max(u.stormPeak, 1e-3);
    if (core > 0.0) {
      let curtains = sampleNoise(vec3f((between - DECK_SPEED * u.cloudWind) / CURTAIN_TILE, 0.1 * STORM_CHURN * u.cloudEvolution / CURTAIN_TILE)).r;
      rate *= 1.0 + core * CURTAIN_CONTRAST * (2.0 * curtains - 1.0);
    }
    let rain = exp(-rainExtinction(rate) * (u.deckBase - SCUD_BELOW) / mu);
    layer = vec4f(mix(under, layer.rgb, rain), rain * layer.a);
  }
  // Under a storm's deck the air is lit by the light under it, not by the sun as the clear sky's
  // is: no golden glow veils its gloom.
  let airlight = mix(skyViewRadiance(dir), under, stormDeckAt(between));
  return throughLitAir(layer, dir, hit.w, airlight);
}
