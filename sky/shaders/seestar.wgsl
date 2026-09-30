// A star as it is seen this frame, worked out once per star by the `stars` pass. A star is a
// point: all it has is a flux, from its magnitude (Pogson: 10^(−0.4 m)), and a colour, from its
// B − V index through its temperature (Ballesteros 2012) to the Planckian locus (Kang et al.
// 2002). The air dims and reddens it (the transmittance LUT), the clouds and the moon hide it (the
// scene's alpha, its view to space), and near the horizon, through more air, it scintillates:
// gently, the index growing as air mass^1.75 (Young 1967).

struct Star {
  direction: vec3f, // J2000 equatorial
  magnitude: f32, // visual, V
  colorIndex: f32, // B − V
}

// How much of a star's blackbody colour the eye sees. Faint light is seen by the colour-blind
// rods: colour fades out over the last magnitudes before STAR_COLOR_LIMIT.
const STAR_SATURATION = 0.7;
const STAR_COLOR_LIMIT = 7.0;
const STAR_COLOR_FADE = 3.0;
// Scintillation index at the zenith, and its cap near the horizon; the twinkling's pace (rad/s).
const SCINTILLATION = 0.04;
const SCINTILLATION_MAX = 0.45;
const TWINKLE_RATE = 3.0;


// Colour of a star of index B − V and magnitude V as the eye sees it, at unit luminance, in
// linear Rec. 709.
fn starColor(colorIndex: f32, magnitude: f32) -> vec3f {
  let t = clamp(4600.0 * (1.0 / (0.92 * colorIndex + 1.7) + 1.0 / (0.92 * colorIndex + 0.62)), 1667.0, 25000.0);
  let k = 1e3 / t;
  let x = select(
    ((-3.0258469 * k + 2.1070379) * k + 0.2226347) * k + 0.24039,
    ((-0.2661239 * k - 0.2343589) * k + 0.8776956) * k + 0.17991,
    t < 4000.0,
  );
  var y: f32;
  if (t < 2222.0) {
    y = ((-1.1063814 * x - 1.3481102) * x + 2.18555832) * x - 0.20219683;
  } else if (t < 4000.0) {
    y = ((-0.9549476 * x - 1.37418593) * x + 2.09137015) * x - 0.16748867;
  } else {
    y = ((3.081758 * x - 5.8733867) * x + 3.75112997) * x - 0.37001483;
  }
  let xyz = vec3f(x / y, 1.0, (1.0 - x - y) / y);
  let rgb = max(mat3x3f(
    3.2404542, -0.969266, 0.0556434,
    -1.5371385, 1.8760108, -0.2040259,
    -0.4985314, 0.041556, 1.0572252,
  ) * xyz, vec3f(0.0));
  let seen = STAR_SATURATION * saturate((STAR_COLOR_LIMIT - magnitude) / STAR_COLOR_FADE);
  return mix(vec3f(1.0), rgb / luminance(rgb), seen);
}

// Calm twinkling: two slow incommensurate waves per star, deeper through more air.
fn twinkle(elevation: f32, seed: f32) -> f32 {
  let airMass = 1.0 / max(elevation, 0.05);
  let depth = min(SCINTILLATION * pow(airMass, 1.75), SCINTILLATION_MAX);
  let phase = TAU * seed;
  let wave = 0.6 * sin(u.time * TWINKLE_RATE * (1.0 + seed) + phase) + 0.4 * sin(u.time * TWINKLE_RATE * 2.7 + 3.0 * phase);
  return 1.0 + depth * wave;
}

// Where a star falls, and its light above the air, once per star and frame. `seed` in [0, 1) is
// the star's own, for its twinkling. Only stars brighter than STAR_HALO_LIMIT have the light for
// their halos to show; the others' light is drawn only as far as their cores reach.
fn seeStar(star: Star, seed: f32) -> SeenStar {
  let dir = toLocal(star.direction);
  let screen = screenPoint(dir);
  if (screen.z <= 0.0) {
    return SeenStar(vec2f(0.0), 0.0, vec3f(0.0));
  }
  let centre = vec2f(0.5 + 0.5 * screen.x, 0.5 - 0.5 * screen.y) * u.outputResolution;
  let reach = select(CORE_REACH, haloReach(), star.magnitude < STAR_HALO_LIMIT);
  // Radiance is flux per solid angle: a pixel spans less of the sky away from the centre.
  let pixelSolidAngle = pow(displayPixelAngle(), 2.0) * pow(screen.z, 3.0);
  let flux = STAR_FLUX * exp2(-0.4 * log2(10.0) * star.magnitude) * twinkle(dir.y, seed);
  return SeenStar(centre, reach, starColor(star.colorIndex, star.magnitude) * flux / pixelSolidAngle);
}

// How much of the light from beyond the air reaches the display at `centre` along local
// direction `dir`: the air's transmittance, times the scene's view to space there (its alpha;
// `scene` is declared by the including shader).
fn throughSky(centre: vec2f, dir: vec3f) -> vec3f {
  let clear = textureSampleLevel(scene, sceneSampler, centre / u.outputResolution, 0.0).a;
  return transmittance(observerRadius(), dir.y) * clear;
}
