// Cirrus: ice crystals falling from small generating cells and drawn out by wind shear into
// fibrous trails (mares' tails), as a thin sheet at u.cirrusAltitude. Soft wisps are noise
// stretched along the flow, broken into patches, and fibres fray their edges. The flow is gently
// domain-warped (Quilez, "Domain Warping"): the wisps keep the jet stream's heading but bend and
// fan a little instead of lying combed in parallel, swelling in places and thinning to nothing. At 8 km the sheet still sees the sun ≈ 3°
// below the ground's horizon, so it keeps glowing pink and orange well into twilight.

// The jet stream's mean heading (unit, x = east, z = north), and its speed relative to the
// cumulus wind.
const JET_HEADING = vec2f(0.8, 0.6);
const JET_SPEED = 2.5;
// Sizes in km of one tile of the noise volume, which holds several features per tile.
// Large, slow bends of the flow, and how far (km) they displace it.
const FLOW_TILE = 140.0;
const FLOW_BEND = 7.0;
// Smaller eddies that curl the wisps into hooks.
const EDDY_TILE = 40.0;
const EDDY_BEND = 0.4;
// Moist patches where cirrus can form at all, and the half-width of their soft edges.
const PATCH_TILE = 120.0;
const PATCH_EDGE = 0.25;
// Wisps: soft, drawn out along the flow, in two octaves so that they swell, thin and break off.
const WISP_TILE = vec2f(50.0, 14.0);
const WISP_OCTAVE = 0.37;
// Fibres: fine strands. They displace the wisps' boundary, fraying their edges into
// strands (the way detail carves the cumulus), and fade out where a pixel spans several.
const FIBRE_TILE = vec2f(10.0, 2.0);
const FRAY = 0.18;
// Fibres wander a little on their own, so that they cross and gather instead of running parallel.
const TWIST_TILE = 8.0;
const TWIST = 1.0;
// Typical fibre spacing, km: the Worley octaves put 4, 8 and 16 across a tile.
const FIBRE_SPACING = FIBRE_TILE.y / 8.0;
// Optical depth of the thickest cirrus: always thin, never hiding the sky for long.
const CIRRUS_DEPTH = 0.6;
// Hexagonal ice scatters forward more tightly than droplets do.
const ICE_FORWARD = 0.75;
const ICE_BACKWARD = -0.2;
const ICE_BACKWARD_WEIGHT = 0.4;
// Light scattered more than once within the sheet, relative to the first scattering.
const ICE_MULTIPLE_SCATTERING = 1.5;

fn icePhase(cosTheta: f32) -> f32 {
  return mix(henyeyGreenstein(cosTheta, ICE_FORWARD), henyeyGreenstein(cosTheta, ICE_BACKWARD), ICE_BACKWARD_WEIGHT);
}

// A smooth displacement field (km) with features about a quarter of `tile` apart.
fn bend(position: vec2f, tile: f32, slice: f32) -> vec2f {
  let a = sampleNoise(vec3f(position / tile, slice)).r;
  let b = sampleNoise(vec3f(position / tile + 0.5, slice + 0.37)).r;
  return vec2f(a, b) - 0.5;
}

// Streak density in [0, 1] at a point of the sheet (km, in the plane) that one pixel spans
// `footprint` km of: wisps where the air is moist enough, frayed into fibres along the flow.
fn streaks(position: vec2f, footprint: f32) -> f32 {
  let drifted = position - u.cloudWind * JET_SPEED;
  let evolution = 0.02 * u.cloudEvolution;
  let patches = sampleNoise(vec3f(drifted / PATCH_TILE, evolution)).r;
  let moist = saturate(remap(patches, 1.0 - u.cirrusCoverage - PATCH_EDGE, 1.0 - u.cirrusCoverage + PATCH_EDGE, 0.0, 1.0));
  if (moist <= 0.0) {
    return 0.0;
  }
  let warped = drifted + FLOW_BEND * bend(drifted, FLOW_TILE, 0.6 + evolution);
  let curled = warped + EDDY_BEND * bend(warped, EDDY_TILE, 0.2 + 2.0 * evolution);
  let flow = vec2f(dot(curled, JET_HEADING), dot(curled, vec2f(-JET_HEADING.y, JET_HEADING.x)));
  let wisps = mix(
    sampleNoise(vec3f(flow / WISP_TILE, 0.3 + evolution)).r,
    sampleNoise(vec3f(flow / (WISP_OCTAVE * WISP_TILE), 0.45 + evolution)).r,
    0.45,
  );
  let twisted = flow + TWIST * bend(flow, TWIST_TILE, 0.9 + evolution);
  let fibres = dot(sampleNoise(vec3f(twisted / FIBRE_TILE, 0.8 + evolution)).gba, vec3f(0.5, 0.3, 0.2));
  let resolved = 1.0 - smoothstep(0.5 * FIBRE_SPACING, 2.0 * FIBRE_SPACING, footprint);
  return moist * smoothstep(0.42, 0.85, wisps + FRAY * resolved * (fibres - 0.5));
}

// rgb: radiance toward the eye; a: transmittance.
fn cirrus(dir: vec3f, lighting: CloudLighting) -> vec4f {
  let r = observerRadius();
  let distance = raySphere(r, dir.y, u.bottomRadius + u.cirrusAltitude).y;
  let p = vec3f(0.0, r, 0.0) + dir * distance;
  // A pixel's span on the sheet, stretched along the view where the ray meets it obliquely.
  let footprint = distance * 2.0 * u.tanHalfFov.y / u.resolution.y / max(dir.y, 0.1);
  let density = streaks(p.xz, footprint);
  if (density <= 0.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let opacity = 1.0 - exp(-CIRRUS_DEPTH * density);
  let keyLight = lighting.keyIlluminance * transmittanceAt(p, lighting.keyDirection);
  let direct = keyLight * icePhase(dot(dir, lighting.keyDirection)) * ICE_MULTIPLE_SCATTERING;
  let layer = vec4f((direct + lighting.sky) * opacity, 1.0 - opacity);
  return throughAir(layer, dir, distance);
}
