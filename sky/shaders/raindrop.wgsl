// The light of one raindrop: a sphere of water is a fisheye lens, so it shows the world around it
// inverted and squeezed into its disc (Garg & Nayar 2004, "Photometric model of a rain drop";
// drawn by refracting the frame itself as in Rousseau, Jolivet & Ghazanfarpour 2006, "Realistic
// real-time rain rendering"). A ray through the disc at a fraction b of its radius from the centre
// enters at incidence i = asin b, bends to r = asin(b/n), and leaves turned 2(i − r) away from the
// side it came in: the centre shows what lies straight behind the drop, the rim the sky some 80°
// beyond, on the other side. The near face mirrors a little more (Fresnel), most at the rim:
// looking up, what lies behind us, the grass and the low sky.
//
// So a drop overhead shows the bright sky behind it in its middle, ringed by the dimmer low sky,
// the dark grass, and its own grazing reflections: a bead of glass, bright at heart and dark at
// the edge, that catches whatever glows around it (gaps in a deck, a low sun's light beneath it).
// What the frame holds is read from the frame (sharp, with the deck's rolls); the rest from the
// dome's rings metered by the exposure pass, and the grass lit by the dome.

const WATER_INDEX = 1.333;
const WATER_REFLECTANCE = 0.02;
// Rain darkens the grass, as water darkens anything rough it soaks (Lekner & Dorf 1988).
const WET_GRASS = 0.5;
// Width of the band at the frame's edge over which its light gives way to the dome's rings, ndc.
const FRAME_EDGE = 0.15;

// The dome's mean along `dir`, between its rings.
fn domeRing(dir: vec3f) -> vec3f {
  let t = clamp((1.0 - dir.y * dir.y) * f32(METERED_RINGS) - 0.5, 0.0, f32(METERED_RINGS - 1u));
  let ring = u32(t);
  let next = min(ring + 1u, METERED_RINGS - 1u);
  return mix(exposure.rings[ring].rgb, exposure.rings[next].rgb, t - f32(ring));
}

// What a drop's faint reflection shows along `dir`: the wet grass below the horizon (lit by the
// whole dome), the dome's rings above it.
fn mirrored(dir: vec3f) -> vec3f {
  if (dir.y <= 0.0) {
    return WET_GRASS * u.groundAlbedo * exposure.dome;
  }
  return domeRing(dir);
}

// What a drop refracts along `dir`: as it mirrors, but sharp from the frame where that is in view.
fn surroundings(dir: vec3f) -> vec3f {
  let ring = mirrored(dir);
  let depth = dot(dir, u.cameraForward);
  if (dir.y <= 0.0 || depth <= 0.0) {
    return ring;
  }
  let ndc = vec2f(dot(dir, u.cameraRight), dot(dir, u.cameraUp)) / (depth * u.tanHalfFov);
  let inFrame = saturate((1.0 - max(abs(ndc.x), abs(ndc.y))) / FRAME_EDGE);
  if (inFrame <= 0.0) {
    return ring;
  }
  let framed = textureSampleLevel(scene, sceneSampler, vec2f(0.5 + 0.5 * ndc.x, 0.5 - 0.5 * ndc.y), 0.0).rgb;
  return mix(ring, framed, inFrame);
}

// The light seen along `dir` through the point `disc` of a drop (in units of its radius, inside the
// unit disc), where `across` and `along` are the sky's directions of the disc's axes.
fn throughDrop(dir: vec3f, across: vec3f, along: vec3f, disc: vec2f) -> vec3f {
  let b = min(length(disc), 0.999);
  let outward = (disc.x * across + disc.y * along) / max(b, 1e-4);
  let cosIncidence = sqrt(1.0 - b * b);
  let turn = 2.0 * (asin(b) - asin(b / WATER_INDEX));
  let refracted = cos(turn) * dir - sin(turn) * outward;
  let reflected = (1.0 - 2.0 * cosIncidence * cosIncidence) * dir + 2.0 * cosIncidence * b * outward;
  let fresnel = WATER_REFLECTANCE + (1.0 - WATER_REFLECTANCE) * pow(1.0 - cosIncidence, 5.0);
  return (1.0 - fresnel) * (1.0 - fresnel) * surroundings(refracted) + fresnel * mirrored(reflected);
}

// The light of a falling drop's streak, `x` across it in units of its radius: the mean over the
// chord of the disc it swept there (two-point Gauss–Legendre).
fn streakLight(dir: vec3f, across: vec3f, along: vec3f, x: f32) -> vec3f {
  let chord = 0.57735 * sqrt(max(1.0 - x * x, 0.0));
  return 0.5 * (throughDrop(dir, across, along, vec2f(x, chord)) + throughDrop(dir, across, along, vec2f(x, -chord)));
}
