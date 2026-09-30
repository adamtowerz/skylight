// The faint stars, which the eye barely separates from the sky and which give it depth: too many
// to list, so procedural. At most one lies in each cell of the field's cube map (FIELD_CELLS a
// face edge), at a random place, with a magnitude drawn from the rising counts of fainter stars,
// and more often toward the plane of the Galaxy, as real faint stars crowd toward it; colours
// follow the naked-eye stars' two populations.

// Magnitudes of the field, from the catalogue's limit to the faintest drawn, and how steeply their
// counts rise: N(< m) ∝ 10^(0.45 m), about 2.8 times as many stars per magnitude (Allen 1973).
const FIELD_BRIGHTEST = 5.5;
const FIELD_FAINTEST = 8.0;
const FIELD_COUNT_SLOPE = 0.45;
// Chance a cell holds a star, far from the Milky Way; toward its plane faint stars are this many
// times as dense, within a scale of galactic latitude (radians).
const FIELD_OCCUPANCY = 0.14;
const FIELD_PLANE_EXCESS = 2.5;
const FIELD_PLANE_SCALE = 0.2;

// A random number per field cell (xy on its face, z the face), and further ones drawn from it.
fn cellSeed(cell: vec3u) -> u32 {
  return pcg(cell.x ^ pcg(cell.y | (cell.z << 16u)));
}

fn unitRandom(seed: u32, draw: u32) -> f32 {
  return f32(pcg(seed + draw) >> 8u) / 16777216.0;
}

// A faint star's magnitude, from a uniform random number, by inverting its counts.
fn fieldMagnitude(x: f32) -> f32 {
  let bright = pow(10.0, FIELD_COUNT_SLOPE * FIELD_BRIGHTEST);
  let faint = pow(10.0, FIELD_COUNT_SLOPE * FIELD_FAINTEST);
  return log2(mix(bright, faint, x)) / (FIELD_COUNT_SLOPE * log2(10.0));
}

// Naked-eye stars' colours are bimodal: A–F dwarfs around B − V ≈ 0.3, K giants around 1.1.
fn fieldColorIndex(x: f32, spread: f32) -> f32 {
  return select(0.3, 1.1, x < 0.45) + 0.25 * (spread - 0.5);
}

// How likely a cell in direction `equatorial` is to hold a faint star.
fn fieldOccupancy(equatorial: vec3f) -> f32 {
  let latitude = asin(abs(toGalactic(equatorial).z));
  return FIELD_OCCUPANCY * (1.0 + FIELD_PLANE_EXCESS * exp(-latitude / FIELD_PLANE_SCALE));
}

// The faint stars near the display pixel centred at `pixel`. Their light covers so few pixels
// that the air and the scene's view to space at this pixel, `throughSky`, stand in for their own.
// The faint star of one field cell as seen this frame, or an empty slot. Stars so near their
// face's edge that it would cut off their light are left out.
fn seeFaintStar(face: u32, cell: vec2u) -> SeenStar {
  let none = SeenStar(vec2f(0.0), 0.0, vec3f(0.0));
  let seed = cellSeed(vec3u(cell, face));
  let chance = unitRandom(seed, 0u);
  // Cells narrow by up to 1/√2 off a face's axes, so a core's reach spans at most this many.
  let margin = sqrt(2.0) * CORE_REACH * displayPixelAngle() / (0.5 * PI) * f32(FIELD_CELLS);
  let position = vec2f(cell) + vec2f(unitRandom(seed, 1u), unitRandom(seed, 2u));
  if (any(position < vec2f(margin)) || any(position > vec2f(f32(FIELD_CELLS) - margin))) {
    return none;
  }
  let direction = cubeDirection(CubePoint(face, position / f32(FIELD_CELLS)));
  if (chance >= fieldOccupancy(direction)) {
    return none;
  }
  let star = Star(direction, fieldMagnitude(unitRandom(seed, 3u)), fieldColorIndex(unitRandom(seed, 4u), unitRandom(seed, 5u)));
  var seen = seeStar(star, unitRandom(seed, 6u));
  seen.light *= throughSky(seen.centre, toLocal(direction));
  return seen;
}
