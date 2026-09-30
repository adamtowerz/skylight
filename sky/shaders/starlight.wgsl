// How a star's light lands on the display, drawn by `post` at the display's own pixels after the
// scene's temporal accumulation, so stars are pin-sharp points that never smear. Its light is
// spread by a point-spread function in display pixels: a Gaussian core, integrated exactly over
// each pixel's square (erf), so every star delivers the same total light wherever it falls within
// a pixel and none sparkles as the sky turns; and a faint wide halo, the lens's (and the eye's)
// scattered light, which only the brightest stars have light enough to show, so they look larger
// as well as brighter. What light each star has is `seestar.wgsl`'s.

// Flux of a magnitude-0 star, as illuminance in the scene's radiance units.
const STAR_FLUX = 7e-6;
// The core Gaussian's standard deviation, in display pixels.
const STAR_SHARPNESS = 0.6;
// The halo's share of the light, and its width (radians, so it is the same angle at any DPR).
const STAR_HALO = 0.15;
const STAR_HALO_WIDTH = 0.005;
// Fainter than this, a star's halo is lost in the sky and is not drawn.
const STAR_HALO_LIMIT = 4.5;
// Stars' light is drawn out to this many standard deviations of the core and of the halo.
const STAR_EXTENT = 4.0;

// Angle across one display pixel at the centre of the view.
fn displayPixelAngle() -> f32 {
  return 2.0 * u.tanHalfFov.y / u.outputResolution.y;
}

// How far from a star's centre its light is drawn, in display pixels: its core's reach, and the
// halo's.
const CORE_REACH = STAR_EXTENT * STAR_SHARPNESS;

fn haloReach() -> f32 {
  return max(CORE_REACH, STAR_EXTENT * STAR_HALO_WIDTH / displayPixelAngle());
}

// Winitzki's (2008) approximation of the error function, accurate to about 1e-4.
fn erf(x: f32) -> f32 {
  let x2 = x * x;
  let a = 0.147;
  return sign(x) * sqrt(1.0 - exp(-x2 * (4.0 / PI + a * x2) / (1.0 + a * x2)));
}

// Share of a unit Gaussian of width `sigma` centred `offset` from a pixel's centre that falls
// within that pixel, per axis.
fn pixelShare(offset: vec2f, sigma: f32) -> vec2f {
  let scale = 1.0 / (sqrt(2.0) * sigma);
  let near = (offset - 0.5) * scale;
  let far = (offset + 0.5) * scale;
  return 0.5 * vec2f(erf(far.x) - erf(near.x), erf(far.y) - erf(near.y));
}

// The radiance a seen star adds to the display pixel centred at `pixel`. Stars whose light is
// drawn only to their cores' reach have too little in their halos to show.
fn starlight(pixel: vec2f, star: SeenStar) -> vec3f {
  let offset = pixel - star.centre;
  let distance2 = dot(offset, offset);
  if (distance2 > star.reach * star.reach) {
    return vec3f(0.0);
  }
  let core = pixelShare(offset, STAR_SHARPNESS);
  var share = (1.0 - STAR_HALO) * core.x * core.y;
  if (star.reach > CORE_REACH) {
    let haloWidth = STAR_HALO_WIDTH / displayPixelAngle();
    share += STAR_HALO * exp(-0.5 * distance2 / (haloWidth * haloWidth)) / (TAU * haloWidth * haloWidth);
  }
  return star.light * share;
}
