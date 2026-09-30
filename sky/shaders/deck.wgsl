// The deck: a low grey layer of stratus and nimbostratus, the sky of a rainy day. Nearest of the
// cloud layers, it hides everything above it where it is whole. It is far too thick and even to
// march: the eye sees only its underside, lit by what diffuses down through it (decklight.wgsl),
// so it is a slab whose column varies across the sky, found where the view ray meets its base.
//
// As the weather brings it in (`weather.ts`) it covers more of the sky: first a broken
// stratocumulus, its cells (the noise volume's Perlin–Worley, after Schneider 2015) clumped in
// patches with blue or sunset between them, then an unbroken grey dome. Its underside is never
// flat: wind shear rolls it into long soft billows across the wind (undulatus), darker where the
// column is deeper and sags lower, lighter between, and Worley lumps mottle it. It drifts slowly,
// at the heaps' angular pace, so the cloud history follows it. Beneath it, where it is thick,
// ragged shreds of scud (fractus) hurry past, lower and so faster across the sky; lit only by the
// deck above and the dim grass below, they are darker than the deck.
//
// At sunset the deck can catch fire from below. From under the deck a sun just below the horizon
// shines upward, along a path that dips beneath the base and climbs back to its height a hundred
// kilometres off toward the sun: if the deck breaks there, the low red light floods in under it
// and lights its underside, most on the flanks of its rolls that face the sun. That is the
// deep orange underside of a Nordic sunset under clouds, gone within minutes as the sun sinks
// out of reach of the base.

// The deck's wind relative to the heaps': at about a third of their height, a third as fast, so
// it drifts across the sky at their angular pace; the scud beneath it hurries past faster still.
const DECK_SPEED = 0.35;
const SCUD_SPEED = 0.6;
// Tiles of the noise volume, km: where the deck is broken or whole, the cells of a broken deck,
// and the lumps that mottle its base.
const DECK_PATCH_TILE = 40.0;
const DECK_CELL_TILE = 3.0;
const LUMP_TILE = 1.0;
// Typical spacing of the lumps, km (the Worley fBm's first octave has 4 cells per tile).
const LUMP_SPACING = LUMP_TILE / 4.0;
// Half the range of the deck's field over which its cover goes from none to nearly whole.
const FIELD_SPREAD = 0.3;
// Share of the deck's field that is its cells (the rest is its patches). Past the edge of a gap
// the column rises quickly to a translucent rim, within DECK_EDGE of the field, then gradually,
// over DECK_BODY, to its full depth, so broken cells are thickest and greyest at their hearts.
const DECK_CELLS = 0.8;
const DECK_EDGE = 0.12;
const DECK_BODY = 0.35;
const DECK_RIM = 0.15;
// Rolls: crest to crest, km, across the wind (unit, x = east, z = north); how far they wander
// (in rolls) over how many km; how deep a column they make and unmake (±), and the lumps too.
const ROLL_SPACING = 0.7;
const ROLL_ACROSS = vec2f(0.93, -0.37);
const ROLL_BEND = 1.2;
const ROLL_BEND_TILE = 12.0;
const ROLL_CONTRAST = 0.35;
const LUMP_CONTRAST = 0.4;
// How far the rolls and the lumps carry the edges of a broken deck, in units of its field: it
// breaks into rows of lumpy cells.
const ROLL_ROWS = 0.1;
const LUMP_EDGES = 0.35;
// How far the base sags under a column one full depth deeper than the mean, km.
const RELIEF = 0.12;
// Scud: how far beneath the base, km; the size of its shreds along and across the wind; how much
// of the sky it covers under a whole deck; and its thickest optical depth.
const SCUD_BELOW = 0.25;
const SCUD_TILE = vec2f(3.0, 1.2);
const SCUD_COVER = 0.25;
const SCUD_DEPTH = 4.0;
// A sun (or moon) lower than this (the sine of ≈ 3°) may light the deck from beneath, through a
// gap between these distances, km; the scud's ragged shreds face it as if they rose this steeply.
const UNDERLIGHT_BELOW = 0.05;
const UNDERLIGHT_REACH = vec2f(10.0, 150.0);
const SCUD_FLANK = 0.3;
// Rain's extinction, km⁻¹ at 1 mm/h, and how it grows with the rate: the Marshall–Palmer drops'
// cross-section, less the half they only diffract forward (Atlas 1953).
const RAIN_EXTINCTION = 0.18;
const RAIN_EXTINCTION_GROWTH = 0.63;

// Where a planet-centred position sits in the deck's drifting field (km), at a wind `speed`
// relative to the heaps'.
fn deckSpace(p: vec3f, speed: f32) -> vec2f {
  return p.xz - speed * u.cloudWind;
}

// The share of the deck's thickest column at `x` (deck space): 0 in its gaps, about
// DECK_MEAN_COLUMN on average where whole, rolled and lumped by as much as a sample standing for
// `footprint` km resolves.
fn deckColumn(x: vec2f, footprint: f32) -> f32 {
  let evolution = 0.3 * u.cloudEvolution;
  let patches = sampleNoise(vec3f(x / DECK_PATCH_TILE, evolution / DECK_PATCH_TILE)).r;
  let cells = sampleNoise(vec3f(x / DECK_CELL_TILE, evolution / DECK_CELL_TILE));
  let bend = ROLL_BEND * sampleNoise(vec3f(x / ROLL_BEND_TILE, 0.37)).r;
  let rolls = cos(TAU * (dot(x, ROLL_ACROSS) / ROLL_SPACING + bend));
  let detail = resolved(LUMP_SPACING, footprint);
  let lumps = (dot(sampleNoise(vec3f(x / LUMP_TILE, evolution / LUMP_TILE)).gba, DETAIL_WEIGHTS) - 0.5) * detail;
  let field = mix(patches, 0.5 * (cells.r + cells.g), DECK_CELLS) + ROLL_ROWS * rolls + LUMP_EDGES * lumps;
  // The field gathers about ½, so the cover is spread over its middle (FIELD_SPREAD), and the last
  // gaps close as the cover nears 1: the deck covers about u.deckCover of the sky, and all of it at 1.
  let threshold = mix(0.5 + FIELD_SPREAD, 0.5 - FIELD_SPREAD, u.deckCover) - smoothstep(0.8, 1.0, u.deckCover);
  let past = field - threshold;
  if (past <= 0.0) {
    return 0.0;
  }
  let whole = DECK_RIM * saturate(past / DECK_EDGE) + (1.0 - DECK_RIM) * saturate(past / DECK_BODY);
  return whole * (1.0 + ROLL_CONTRAST * rolls * cells.r + 2.0 * LUMP_CONTRAST * lumps);
}

// How far the base lies below its mean height, km: it sags where the column is deep.
fn sag(column: f32) -> f32 {
  return RELIEF * (column - DECK_MEAN_COLUMN);
}

// Optical depth of the deck above the planet-centred point `p` on its base.
fn deckDepthAt(p: vec3f, footprint: f32) -> f32 {
  return u.deckDepth * deckColumn(deckSpace(p, DECK_SPEED), footprint);
}

// Radiance that cloud at the planet-centred point `q`, of optical depth `tau`, reflects down from
// a key light low enough to shine up under the deck: through the gap where its path climbs back to
// the base's height from `x` (deck space), onto the cloud as far as it faces the light, which is
// more where it `rises` toward the light (km per km), reflected by the slab above.
fn underlight(x: vec2f, q: vec3f, tau: f32, rise: f32) -> vec3f {
  let key = keyLight();
  let across = max(length(key.direction.xz), 1e-3);
  let toward = key.direction.xz / across;
  // A path dipping at elevation −e from the base climbs back to its height 2R tan e away.
  let dip = max(-key.direction.y, 0.0) / across;
  let gap = x + toward * clamp(2.0 * u.bottomRadius * dip, UNDERLIGHT_REACH.x, UNDERLIGHT_REACH.y);
  let open = 1.0 - saturate(deckColumn(gap, 1.0) / DECK_MEAN_COLUMN);
  let facing = (rise * across - key.direction.y) / sqrt(1.0 + rise * rise);
  if (facing <= 0.0 || open <= 0.0) {
    return vec3f(0.0);
  }
  let irradiance = key.illuminance * transmittanceAt(q, key.direction) * facing * open;
  return irradiance * slabReflectance(tau, max(facing, 0.01)) / PI;
}

// How far the base at `x` (deck space) rises toward the key light, km per km.
fn baseRise(x: vec2f, column: f32, footprint: f32) -> f32 {
  let step = 0.1;
  let toward = normalize(keyLight().direction.xz);
  return (sag(column) - sag(deckColumn(x + toward * step, footprint))) / step;
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
  if (column > 0.0) {
    let tau = u.deckDepth * column;
    let glow = deckGlow(dir, hit.xyz, tau, lighting.sky);
    var light = glow.rgb;
    if (lowLight) {
      light += underlight(x, hit.xyz, tau, baseRise(x, column, hit.w * footprint));
    }
    layer = vec4f(light, exp(-tau / mu) + glow.a);
  }
  // The light under the deck, on average: what shines on the scud from above, and on the rain.
  let deckMean = deckGlow(vec3f(0.0, 1.0, 0.0), hit.xyz, DECK_MEAN_COLUMN * u.deckDepth, lighting.sky);
  let under = mix(lighting.sky, deckMean.rgb + deckMean.a * lighting.sky, u.deckCover);

  // Scud: thin, so lit as a slab by the light under the deck above it and the grass below.
  let scudCover = SCUD_COVER * smoothstep(0.6, 1.0, u.deckCover);
  if (scudCover > 0.0) {
    let low = onLayer(dir, u.deckBase - SCUD_BELOW);
    let along = deckSpace(low.xyz, SCUD_SPEED);
    let s = vec2f(dot(along, ROLL_ACROSS), dot(along, vec2f(-ROLL_ACROSS.y, ROLL_ACROSS.x)));
    let shreds = sampleNoise(vec3f(s / SCUD_TILE, 0.8 * u.cloudEvolution));
    let ragged = shreds.r - 0.5 * shreds.g * resolved(SCUD_TILE.y / 8.0, low.w * footprint);
    let tauScud = SCUD_DEPTH * saturate((ragged - (1.0 - scudCover)) / DECK_EDGE);
    if (tauScud > 0.0) {
      let reflected = slabReflectance(tauScud, 0.5);
      var scud = under * (max(1.0 - reflected - exp(-2.0 * tauScud), 0.0) + u.groundAlbedo * reflected);
      if (lowLight) {
        scud += underlight(deckSpace(low.xyz, DECK_SPEED), low.xyz, tauScud, SCUD_FLANK);
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
