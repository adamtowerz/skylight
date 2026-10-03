// Rain falling on the eye from the grey overhead, drawn by `post` at the display's own pixels
// after the scene's temporal accumulation, like the stars, so every streak is crisp and none is
// smeared by the cloud history.
//
// We lie on our back, so the rain comes down at us: every drop falls along the same line, its
// terminal fall plus the wind it is carried in (gusts.ts), and perspective makes their paths
// radiate from one vanishing point, upwind of the zenith, and converge again on the opposite one
// below the horizon. A light rain's breeze leans that line a little, so it streams gently out of
// the sky overhead, lengthening toward the edges of the view; a storm's outflow leans it far over,
// so its vanishing point leaves the view and the drops sweep across it in slanting, nearly
// parallel sheets. So the drops are placed in the frame of that fall (the rain layers of
// Tatarchuk 2006, "Artist-directable real-time rain rendering in city environments", turned
// upward): nested cylinders about the fall line through the eye, one layer each, twice as wide as
// the last. A drop on a cylinder of radius r at height z
// is seen at angle θ from the vanishing point with cot θ = z / r, so as it falls its cot θ runs
// down at a steady v / r. Each layer is a lattice over (azimuth about the fall line, cot θ)
// scrolling at that pace, at most one drop per cell, hashed; a pixel looks only at the few cells
// whose drops can reach it.
//
// Only the nearest few metres are drawn drop by drop. Further out a drop is narrower than a pixel,
// so its share of one falls as 1/r while the drops behind a pixel grow as r²: far rain sums to an
// even veil, which the deck's rain already is (deck.wgsl).
//
// Each drop is a streak: where it fell during the eye's exposure (about as long as the eye holds an
// image, so each streak joins the next frame's and the fall reads as motion, not as flecks), though
// never longer than SMEAR: the eye sees far less smear behind a fast-moving thing than it holds an
// image for (Burr 1980, "Motion smear"), so a gale's drops stay strokes rather than faint threads
// across the whole view. It is as wide as the drop, and blurred by the eye's focus on the sky, so
// the nearest drift past large and soft. Across it the streak carries the drop's own light
// (raindrop.wgsl): a bead of glass, bright at heart where it shows the sky behind it, dark at the
// rim where it shows the low sky and the grass, warm where it catches a glow. Under an even deck
// that light differs from the sky behind it by a few per cent, so its contrast is amplified, in
// stops and bounded, keeping its sign and colour. A streak veils what lies behind it by the share
// of the exposure the drop spent over each point (round-ended, and longest down its middle, as a
// sphere sweeps), box-filtered over its blur and the pixel's width together, so each carries the
// same light wherever it falls and none crawls or sparkles.
//
// Drops near the vanishing point fall almost straight at the eye: they barely move on the screen,
// so instead of streaks they would be still specks, and further than a pixel's width they would be
// dust. Those fade out, leaving a calm opening the rain streams out of.
//
// How much rain falls sets its drops after Marshall & Palmer 1948: how many there are, and how
// large, and so how fast they fall (Atlas et al. 1973). Light rain is a few millimetres an hour,
// a storm's downpour tens: the same drops, ten times as many, twice as large and faster, so each
// layer holds up to RAIN_LATTICES lattices, filled one after the next as the rain grows. The
// gusts (gusts.ts) lean the fall over and swell the rain in surges; the lattices scroll by the
// distance the drops have fallen (rainfall.ts), so a gust's larger, faster drops speed up
// smoothly, and a drop that a heavier rain adds fades in rather than appearing mid-flight.

const RAIN_LAYERS = 3;
// Radius of the nearest layer, m; each next is twice as wide.
const NEAREST_RAIN = 0.2;
// A cell of the nearest layer's lattice, in azimuth (radians), and each layer's in cot θ. Further
// layers' cells narrow as their radius to the power 1.5 and shorten about as its square root, so
// they hold few enough drops to have at most one (the shell's volume grows as r³), are still
// longer than their drops' streaks and wider than their drops. Each is a whole fraction of the
// fold of the distance fallen (rainfall.ts: 0.2, 0.3 and 0.4 m of fall), so the fold leaves no seam.
const RAIN_COLUMN = 0.5;
const RAIN_ROWS = array(1.0, 0.75, 0.5);
const RAIN_FOLD = 1200.0;
// Lattices per layer, and the most drops one may hold per cell: a cell's chance of a drop, beyond
// which the next lattice takes up the rest. A drop fades in over the last RAIN_FADING of its
// cell's chance, so one that a gust adds never pops.
const RAIN_LATTICES = 3;
const RAIN_CELL_CAP = 0.5;
const RAIN_FADING = 0.3;
// Drops further than this from the eye, m, fade out (their rain is the deck's veil), and those
// closer than this above the grass fade in.
const RAIN_FAR = 6.0;
const RAIN_GROUND = 0.3;
// The eye's exposure, s (about as long as it holds an image), and its pupil, m, focused on the sky.
const EXPOSURE_TIME = 0.016;
const APERTURE = 0.004;
// The longest streak seen, radians, for drops of the nearest layer; further layers', as the
// square root of their nearness.
const SMEAR = 0.2;
// Drops are drawn this much larger than they are, as the sun and moon are, and their contrast
// amplified (BEAD_CONTRAST): a few drops of light rain must be seen. In heavier rain than
// SPARSE_RAIN mm/h both fall away as the fourth root of the rate, since a torrent is seen by its
// numbers: its drops stay finer and pour past in long thin streaks.
const DROP_SCALE = 11.0;
const SPARSE_RAIN = 2.0;
// Drops smaller than this, mm, are too faint to see one by one; of the rest, this share is drawn.
const SMALLEST_DROP = 1.0;
const RAIN_DRAWN = 0.6;
// Streaks fade in as they grow from this many times as long as they are wide to the next, and
// drops as they grow from this many pixels wide to the next.
const STREAKING = vec2f(1.0, 3.0);
// And as their streaks grow from this many pixels long to the next: shorter ones would be dust
// about the vanishing point, where a downpour's many fine drops come almost straight at the eye.
const STREAK_PIXELS = vec2f(4.0, 14.0);
const RESOLVED = vec2f(0.5, 1.5);
// Where across a drop, in units of its radius, its light is about its mean: a drop blurred much
// wider than itself shows that light all across.
const BEAD_MEAN = 0.7;
// How many times more a drop's brightness departs from what lies behind it than it does, in
// stops, and the most it may then depart, darker and brighter. Under an even grey deck a drop
// shows nearly the sky it hides and light rain all but vanishes from a still; the eye, sensitive
// to anything that moves, sees it anyway. Each colour's contrast keeps its sign, and a drop
// against a sky of strong contrasts (a broken deck at sunset) is held in.
const BEAD_CONTRAST = 20.0;
const BEAD_STOPS = vec2f(3.5, 1.5);

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
  let rate = rainOver(vec2f(0.0));
  if (rate <= 0.0) {
    return behind;
  }
  // Marshall–Palmer: N(D) = N₀ e^(−ΛD) with N₀ = 8000 m⁻³ mm⁻¹; the median drop by volume is 3.67 / Λ.
  let slope = 4.1 * pow(rate, -0.21); // mm⁻¹
  let typical = 3.67 / slope; // mm
  let drawn = RAIN_DRAWN * 8000.0 / slope * exp(-slope * SMALLEST_DROP); // per m³

  let amplified = sqrt(sqrt(min(SPARSE_RAIN / rate, 1.0)));

  let dir = rayThrough(pixelNdc(pixel, u.outputResolution));
  let coming = vec3f(-u.rainWind.x, u.rainFallSpeed, -u.rainWind.y);
  let speed = length(coming);
  let fall = coming / speed;
  let across = normalize(cross(fall, vec3f(0.0, 0.0, 1.0)));
  let around = cross(fall, across);
  let cosTheta = dot(dir, fall);
  let sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 1e-8));
  let azimuth = atan2(dot(dir, around), dot(dir, across)) + PI;
  let height = cosTheta / sinTheta;
  // The sky's directions about this pixel: along the drops' fall away from the vanishing point,
  // and across it, the way azimuth grows.
  let outward = (dir - cosTheta * fall) / sinTheta;
  let downstream = cosTheta * outward - sinTheta * fall;
  let sideways = cross(dir, downstream);
  // A streak is short beside its distance from the vanishing point, so about this pixel cot θ maps
  // to angle linearly: dθ = −sin²θ d(cot θ); and every drop that can reach it is as far as it is.
  let slant = sinTheta * sinTheta;
  // A display pixel spans less of the sky away from the centre of the view.
  let pixelAngle = displayPixelAngle() * pow(dot(dir, u.cameraForward), 1.5);

  var veil = 0.0;
  var looked = 0.0;
  for (var layer = 0; layer < RAIN_LAYERS; layer++) {
    let radius = NEAREST_RAIN * exp2(f32(layer));
    let distance = radius / sinTheta;
    let nearness = NEAREST_RAIN / radius;
    let cellSize = RAIN_ROWS[layer];
    let columns = round(TAU / (RAIN_COLUMN * pow(nearness, 1.5)));
    let column = TAU / columns;
    // A layer's drops fall as one, at its typical drop's pace, so its lattice scrolls as one, by
    // the distance they have fallen (of cot θ: a drop at height z on the cylinder is at z / r).
    let rows = round(RAIN_FOLD / (radius * cellSize));
    let scrolled = u.rainFallen / radius;
    let streak = min(speed / radius * EXPOSURE_TIME, SMEAR * sqrt(nearness) / slant);
    let travel = streak * slant;
    // The drops' apparent size, and the blur they are seen through (with the pixel's own box).
    let size = DROP_SCALE * amplified * 1e-3 * typical / distance;
    let blur = length(vec2f(APERTURE / distance, pixelAngle));
    let fade = smoothstep(0.0, RAIN_GROUND, distance * dir.y)
      * (1.0 - smoothstep(0.5 * RAIN_FAR, RAIN_FAR, distance))
      * smoothstep(STREAKING.x, STREAKING.y, travel / size)
      * smoothstep(STREAK_PIXELS.x, STREAK_PIXELS.y, travel / pixelAngle)
      * smoothstep(RESOLVED.x, RESOLVED.y, size / pixelAngle);
    if (fade <= 0.0) {
      continue;
    }
    // Drops in a cell: those in its share of the shell between this cylinder and the next, shared
    // out over as many lattices as it takes.
    let drops = drawn * 0.75 * radius * radius * radius * column * cellSize;
    let reach = 0.5 * (1.4 * size + blur);
    let aside = reach / (sinTheta * column);
    let up = (streak + reach / slant) / cellSize;
    let down = reach / (slant * cellSize);
    for (var lattice = 0; lattice < RAIN_LATTICES; lattice++) {
      let chance = min(drops - f32(lattice) * RAIN_CELL_CAP, RAIN_CELL_CAP);
      if (chance <= 0.0) {
        break;
      }
      // Where the pixel lies in the lattice (each lattice set off from the last by part of a cell),
      // and how far into the cells around it a drop's light can reach (half its widest, plus its
      // blur): across, and up from below along its streak and down from above. Only those cells are
      // looked at, most often just the pixel's own.
      let shift = vec2f(0.5, 0.37) * f32(lattice);
      let c = azimuth / column + shift.x;
      let r = (height + scrolled) / cellSize + shift.y;
      let within = fract(vec2f(c, r));
      // The one neighbour across and the one along that a drop could reach this pixel from, if any.
      let toward = vec2f(select(1.0, -1.0, within.x < 0.5), select(1.0, -1.0, within.y < up));
      let near = vec2<bool>(within.x < aside || within.x > 1.0 - aside, within.y < up || within.y > 1.0 - down);
      let seed = pcg(u32(layer + 3 * lattice));
      for (var i = 0; i < 4; i++) {
        let neighbour = vec2<bool>((i & 1) == 1, (i & 2) == 2);
        if (any(neighbour & !near)) {
          continue;
        }
        let cell = floor(vec2f(c, r)) + select(vec2f(0.0), toward, neighbour);
        let wrapped = vec2u(u32((cell.x + columns) % columns), u32(((cell.y % rows) + rows) % rows));
        let random = cellRandom(wrapped, seed);
        let present = saturate((chance - random.w) / (RAIN_FADING * chance));
        if (present <= 0.0) {
          continue;
        }
        // The middle of the streak: where the drop was halfway through the exposure.
        let middle = (cell.y - shift.y + random.y) * cellSize - scrolled + 0.5 * streak;
        var offset = azimuth - (cell.x - shift.x + random.x) * column;
        offset -= TAU * round(offset / TAU);
        let drop = size * (0.6 + 0.8 * random.z);
        // A round drop sweeps a streak with round ends: its share of a point ramps up over one
        // drop's width at each end, and it lingers over the middle of the streak longer than its
        // edges (as its chord there), on top of the blur.
        let wide = overlap(offset * sinTheta, drop, blur);
        let along = overlap((middle - height) * slant, travel, blur + drop);
        // Where across the drop this pixel looks, softened toward its mean light by the blur.
        let x = clamp(2.0 * offset * sinTheta / drop, -1.0, 1.0);
        let sharp = drop / (drop + blur);
        let bead = sign(x) * mix(BEAD_MEAN, abs(x), sharp);
        // Each point of the streak holds the drop for this share of the exposure.
        let held = present * fade * wide * along * sqrt(1.0 - bead * bead) * drop / (travel + drop);
        if (held <= 0.0) {
          continue;
        }
        looked += held * bead;
        veil += held;
      }
    }
  }
  if (veil <= 0.0) {
    return behind;
  }
  // Streaks seldom cross: where they do, they share what they hide and show one drop's light,
  // seen where across them this pixel looks on average.
  let seen = streakLight(dir, sideways, downstream, looked / veil);
  // In heavy rain its colour is amplified less than its brightness, as its contrast is.
  let hued = log2(max(seen, vec3f(1e-12)) / max(behind, vec3f(1e-12)));
  let grey = log2(max(luminance(seen), 1e-12) / max(luminance(behind), 1e-12));
  let stops = mix(vec3f(grey), hued, amplified * amplified);
  let most = select(vec3f(BEAD_STOPS.y), vec3f(BEAD_STOPS.x), stops < vec3f(0.0));
  let shown = behind * exp2(most * tanh(BEAD_CONTRAST * amplified * stops / most));
  return mix(behind, shown, min(veil, 1.0));
}
