// Rain falling on the eye from the grey overhead, drawn by `post` at the display's own pixels
// after the scene's temporal accumulation, like the stars, so every streak is crisp and none is
// smeared by the cloud history.
//
// We lie on our back, so the rain comes straight down at us: every drop falls along the same line,
// and perspective makes their paths radiate from one vanishing point, the zenith tilted a little
// upwind by the breeze, lengthening toward the edges of the view. So the drops are placed in the
// frame of that fall (the rain layers of Tatarchuk 2006, "Artist-directable real-time rain
// rendering in city environments", turned upward): nested cylinders about the fall line through
// the eye, one layer each, twice as wide as the last. A drop on a cylinder of radius r at height z
// is seen at angle θ from the vanishing point with cot θ = z / r, so as it falls its cot θ runs
// down at a steady v / r. Each layer is a lattice over (azimuth about the fall line, cot θ)
// scrolling at that pace, at most one drop per cell, hashed; a pixel looks only at the few cells
// whose drops can reach it.
//
// Only the nearest few metres are drawn drop by drop. Further out a drop is narrower than a pixel,
// so its share of one falls as 1/r while the drops behind a pixel grow as r²: far rain sums to an
// even veil, which the deck's rain already is (deck.wgsl).
//
// Each drop is a streak: where it fell during the eye's exposure, as wide as the drop, and blurred
// by the eye's focus on the sky, so the nearest drift past large and soft. Its light is the
// photometric model of Garg & Nayar 2004 ("Photometric model of a rain drop"): a drop is a tiny
// fisheye onto nearly the whole dome above it, so it shows a share of the dome's mean radiance
// (the exposure pass meters it) whatever lies behind it: seen from below, a grey fleck. A streak
// veils what lies behind it by the share of the exposure the drop spent over each point,
// box-filtered over its blur and the pixel's width together, so each carries the same light
// wherever it falls and none crawls or sparkles.
//
// How much rain falls sets its drops after Marshall & Palmer 1948: how many there are, and how
// large, and so how fast they fall (Atlas et al. 1973). Light rain is a few millimetres an hour;
// heavier rain is the same drops, more and larger: only `rainRate` need grow.

const RAIN_LAYERS = 4;
// Radius of the nearest layer, m; each next is twice as wide.
const NEAREST_RAIN = 0.4;
// A cell of the nearest layer's lattice, in azimuth (radians) and in cot θ; further layers' cells
// shrink as the square root of their radius, so their drops crowd closer on the screen.
const RAIN_CELL = 0.5;
// Drops further than this from the eye, m, fade out (their rain is the deck's veil), and those
// closer than this above the grass fade in.
const RAIN_FAR = 6.0;
const RAIN_GROUND = 0.3;
// The eye's exposure, s (a quick one, so that streaks are short enough to show), and its pupil,
// m, focused on the sky.
const EXPOSURE_TIME = 0.012;
const APERTURE = 0.004;
// Drops are drawn this much larger than they are, as the sun and moon are.
const DROP_SCALE = 12.0;
// Drops smaller than this, mm, are too faint to see one by one; of the rest, this share is drawn.
const SMALLEST_DROP = 1.0;
const RAIN_DRAWN = 0.1;
// Share of the dome's light a drop shows. Garg & Nayar find a drop shows ≈ 0.94 of the light in
// its field, but seen from below its face is ringed by total internal reflection and its lower
// surface mirrors the grass: against an overcast, falling drops are grey, as snowflakes are.
const DROP_SHOWS = 0.5;
// The breeze near the ground, m/s (x = east, z = north): it tilts the fall a little.
const RAIN_BREEZE = vec2f(0.8, 0.3);
// The lattice scrolls with time folded over this period, s, by a whole number of cells.
const RAIN_PERIOD = 600.0;

// Terminal fall speed of a drop `diameter` mm across, m/s (Atlas, Srivastava & Sekhon 1973).
fn fallSpeed(diameter: f32) -> f32 {
  return 9.65 - 10.3 * exp(-0.6 * diameter);
}

// Random numbers for a cell of a layer's lattice, seeded by `layer`: w in [0, 1) at 24 bits, which
// decides whether the cell holds a drop; x, y (where in the cell) and z (how large) at 10 bits.
fn cellRandom(cell: vec2u, layer: u32) -> vec4f {
  let a = pcg(cell.x ^ pcg(cell.y ^ layer));
  let b = pcg(a);
  return vec4f(vec3f(vec3u(b, b >> 10u, b >> 20u) & vec3u(1023u)) / 1024.0, f32(a >> 8u) / 16777216.0);
}

// How much of a window `window` wide, centred `offset` from the middle of an interval `width`
// wide, the interval covers: a pixel's share of a streak, or of a drop blurred wider than a pixel.
fn overlap(offset: f32, width: f32, window: f32) -> f32 {
  let near = max(offset - 0.5 * window, -0.5 * width);
  let far = min(offset + 0.5 * window, 0.5 * width);
  return max(far - near, 0.0) / window;
}

// The rain falling in front of the display pixel centred at `pixel`, where the scene (and the
// stars) are `behind`.
fn rain(pixel: vec2f, behind: vec3f) -> vec3f {
  if (u.rainRate <= 0.0) {
    return behind;
  }
  // Marshall–Palmer: N(D) = N₀ e^(−ΛD) with N₀ = 8000 m⁻³ mm⁻¹; the median drop by volume is 3.67 / Λ.
  let slope = 4.1 * pow(u.rainRate, -0.21); // mm⁻¹
  let typical = 3.67 / slope; // mm
  let drawn = RAIN_DRAWN * 8000.0 / slope * exp(-slope * SMALLEST_DROP); // per m³

  let dir = rayThrough(pixelNdc(pixel, u.outputResolution));
  let fall = normalize(vec3f(-RAIN_BREEZE.x, fallSpeed(typical), -RAIN_BREEZE.y));
  let across = normalize(cross(fall, vec3f(0.0, 0.0, 1.0)));
  let around = cross(fall, across);
  let cosTheta = dot(dir, fall);
  let sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 1e-8));
  let azimuth = atan2(dot(dir, around), dot(dir, across)) + PI;
  let height = cosTheta / sinTheta;
  // A streak is short beside its distance from the vanishing point, so about this pixel cot θ maps
  // to angle linearly: dθ = −sin²θ d(cot θ); and every drop that can reach it is as far as it is.
  let slant = sinTheta * sinTheta;
  // A display pixel spans less of the sky away from the centre of the view.
  let pixelAngle = displayPixelAngle() * pow(dot(dir, u.cameraForward), 1.5);
  let time = u.time % RAIN_PERIOD;

  var veil = 0.0;
  for (var layer = 0; layer < RAIN_LAYERS; layer++) {
    let radius = NEAREST_RAIN * exp2(f32(layer));
    let distance = radius / sinTheta;
    let fade = smoothstep(0.0, RAIN_GROUND, radius * height) * (1.0 - smoothstep(0.5 * RAIN_FAR, RAIN_FAR, distance));
    if (fade <= 0.0) {
      continue;
    }
    let cellSize = RAIN_CELL * inverseSqrt(radius / NEAREST_RAIN);
    let columns = round(TAU / cellSize);
    let column = TAU / columns;
    // A layer's drops fall as one, at its typical drop's pace, so its lattice scrolls as one: by a
    // whole number of cells per period, so time folds over without a seam.
    let rows = round(fallSpeed(typical) * RAIN_PERIOD / (radius * cellSize));
    let speed = rows * cellSize / RAIN_PERIOD; // of cot θ, per second
    let streak = speed * EXPOSURE_TIME;
    let travel = streak * slant;
    // Drops in a cell: those in its share of the shell between this cylinder and the next.
    let chance = drawn * 0.75 * radius * radius * radius * column * cellSize;
    // The drops' apparent size, and the blur they are seen through (with the pixel's own box).
    let size = DROP_SCALE * 1e-3 * typical / distance;
    let blur = length(vec2f(APERTURE / distance, pixelAngle));
    // Where the pixel lies in the lattice, and how far into the cells around it a drop's light can
    // reach (half its widest, plus its blur): across, and up from below along its streak and down
    // from above. Only those cells are looked at, most often just the pixel's own.
    let c = azimuth / column;
    let r = (height + speed * time) / cellSize;
    let reach = 0.5 * (1.4 * size + blur);
    let sideways = reach / (sinTheta * column);
    let up = (streak + reach / slant) / cellSize;
    let down = reach / (slant * cellSize);
    let within = fract(vec2f(c, r));
    // The one neighbour across and the one along that a drop could reach this pixel from, if any.
    let toward = vec2f(select(1.0, -1.0, within.x < 0.5), select(1.0, -1.0, within.y < up));
    let near = vec2<bool>(within.x < sideways || within.x > 1.0 - sideways, within.y < up || within.y > 1.0 - down);
    let seed = pcg(u32(layer));
    var held = 0.0;
    for (var i = 0; i < 4; i++) {
      let neighbour = vec2<bool>((i & 1) == 1, (i & 2) == 2);
      if (any(neighbour & !near)) {
        continue;
      }
      let cell = floor(vec2f(c, r)) + select(vec2f(0.0), toward, neighbour);
      let wrapped = vec2u(u32((cell.x + columns) % columns), u32(((cell.y % rows) + rows) % rows));
      let random = cellRandom(wrapped, seed);
      if (random.w >= chance) {
        continue;
      }
      // The middle of the streak: where the drop was halfway through the exposure.
      let middle = (cell.y + random.y) * cellSize - speed * time + 0.5 * streak;
      var offset = azimuth - (cell.x + random.x) * column;
      offset -= TAU * round(offset / TAU);
      let drop = size * (0.6 + 0.8 * random.z);
      let wide = overlap(offset * sinTheta, drop, blur);
      let along = overlap((middle - height) * slant, travel + drop, blur);
      // Each point of the streak holds the drop for this share of the exposure.
      held += wide * along * drop / (travel + drop);
    }
    veil += fade * held;
  }
  return mix(behind, DROP_SHOWS * exposure.dome, min(veil, 1.0));
}
