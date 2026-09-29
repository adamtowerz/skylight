// Altocumulus: a mackerel sky, a thin layer of small rounded cloudlets at
// u.altocumulusAltitude (≈ 5 km), between the heaps below and the cirrus above. Wind shear across
// a moist, stable layer rolls it up into billows (Kelvin–Helmholtz), whose crests lie
// perpendicular to the shear and break into rows of cloudlets with blue between them. So the
// cloudlets are cells: an ordered cellular (Worley 1996) lattice in the plane of the layer, one row
// per billow crest along the shear, each cell a soft dome of its own size; the rows bend with the
// flow (domain warping, Quilez), their billows swell and fade in wave trains, and fine Worley
// detail frays each cloudlet's rim. Patches of moist air decide where the field forms at all, and
// where the mood asks for it the cloudlets merge into a flatter altostratus sheet.
//
// The layer is thin, so it is crossed in a few steps, each of which takes the height to run
// linearly along it and integrates, exactly, the share of it below the cloudlet tops: a slab march
// with no contour lines at any step count. A cloudlet's light comes through the atmosphere at its
// own height (`transmittanceAt`), so at 5 km it keeps the sun for minutes after the ground and the
// heaps have lost it, burning orange, rose and pink over the whole sky before it greys, and the
// moon lights it at night. The light's way through a cloudlet is found analytically rather than
// marched: out to its rim across the plane (a ray against its disk) or out through its top or
// flat base, whichever comes first, so under a low sun each cloudlet has a lit side and a shaded
// one, sharply and without the aliasing of long light steps. It scatters with the cumulus's
// dual-lobe phase (the silver lining) and multiple-scattering octaves, those of a high light even
// under a grazing one: a thin layer has no deep body for the light to diffuse through.
// Cells a sample cannot resolve give way to their mean, so toward the horizon the field merges
// into a fine even texture instead of shimmering under the interleaved march.

// Depth of the layer, km: a few hundred metres, twice that where it merges into altostratus.
const ALTO_DEPTH = 0.25;
// The layer's wind relative to the heaps': the same westerly, twice as fast at twice their
// middle height, so across the sky it drifts at the same angular pace as they do, and the cloud
// history, carried back along the heaps' drift (temporal.wgsl), follows it exactly too.
const ALTO_SPEED = 2.0;
// Heading of the wind shear across the layer (unit, x = east, z = north), close to the wind's.
const SHEAR = vec2f(0.93, -0.37);
// A cell, km: along the shear, one billow crest to the next; across it, cloudlet to cloudlet
// along a crest, where the roll breaks up. Cloudlets take the cell's shape, drawn out along
// their crest.
const CELL = vec2f(0.38, 0.65);
// How far each cloudlet strays from the lattice, in cells, along the shear and across it: little
// off its crest, so the rows stay rows, more along it, so they never read as a grid. And how far
// it wanders as the field churns.
const CELL_JITTER = vec2f(0.2, 0.5);
const CELL_WANDER = 0.08;
// A cloudlet's radius in cells where the field is thickest (at 0.5 neighbours touch), and how far
// radii vary from cell to cell (a share of it).
const CLOUDLET_RADIUS = 0.45;
const CLOUDLET_SIZES = vec2f(0.35, 1.3);
// The furthest a cloudlet reaches from its centre, in cells, before the fray swells it by up to
// 1 / (1 − ALTO_FRAY / 2): within the 3 × 3 cells searched, whose other cloudlets lie at least
// 1.5 − CELL_JITTER.y / 2 − CELL_WANDER away, so none is ever cut off at a cell's edge.
const CLOUDLET_REACH = 0.65;
// Typical spacing of the cloudlets that lookups must resolve, km: the small ones between the big.
const CLOUDLET_SPACING = 0.5 * CELL.x;
// The billows: along the shear their crests come every BILLOW km, and cloudlets swell on them and
// shrink between them (a share of the radius), so the field lies in rows; over wave trains
// WAVE_TRAIN km long the billows themselves swell and fade.
const BILLOW = 1.2;
const BILLOW_SWELL = 0.45;
const WAVE_TRAIN = 7.0;
const WAVE_SWELL = 0.25;
// The flow bends the rows over tens of km.
const ROW_BEND_TILE = 60.0;
const ROW_BEND = 3.0;
// Moist patches where the layer forms, and the half-width of their soft edges.
const ALTO_PATCH_TILE = 30.0;
const ALTO_PATCH_EDGE = 0.2;
// Eddies about the size of a cloudlet push the cells about, km, so that no two cloudlets share a
// shape and neighbours merge into lumps and short rolls.
const CLOUDLET_EDDY_TILE = 4.0;
const CLOUDLET_EDDY = 0.25;
// How far merging neighbours round off the seam between them, in units of their radii.
const MERGE = 0.35;
// Worley detail finer than the cells, which lumps each cloudlet's outline (in units of its
// radius) and mottles its body (a share of its density), so it reads as a tuft, not a blot. Only
// the volume's finer Worley octaves (B and A, 8 and 16 cells across a tile and up): the coarsest
// one's flat facets, as large as a cloudlet, would cut it into a polygon.
const FRAY_TILE = 3.0;
const FRAY_WEIGHTS = vec2f(0.6, 0.4);
const ALTO_FRAY = 0.8;
const MOTTLE = 0.5;
const FRAY_SPACING = FRAY_TILE / 16.0;
// Extinction inside a cloudlet, km⁻¹: thinner than a heap's core, so rims glow through.
const ALTO_EXTINCTION = 24.0;
// Churn of the cells, km of the noise volume's evolution per full cycle.
const ALTO_CHURN = 2.0;
// Steps through the layer: a few, and more where the ray crosses resolved cloudlets obliquely, at
// least one per ALTO_STRIDE km across the plane.
const ALTO_STEPS = vec2f(4.0, 12.0);
const ALTO_STRIDE = 0.2;
// The light's longest way through the layer, km, where the veil of unresolved cloudlets stands in
// for them; and the mean density along its way out of a cloudlet, relative to the sample's.
const ALTO_LIGHT_REACH = 1.2;
const WAY_OUT = 0.6;

// The layer over a point: how much of it the moist air fills, and how far the flow has bent it.
struct AltoWeather {
  cover: f32,
  warp: vec2f,
}

// The layer's base and depth, planet-centred km.
fn altoBase() -> f32 {
  return u.bottomRadius + u.altocumulusAltitude - 0.5 * altoDepth();
}

fn altoDepth() -> f32 {
  return ALTO_DEPTH * (1.0 + u.altocumulusSheet);
}

// Height within the layer: 0 at its base, 1 at its top.
fn altoHeight(p: vec3f) -> f32 {
  return (length(p) - altoBase()) / altoDepth();
}

// Where a point of the layer sits in its moving field (km, in the plane).
fn altoSpace(p: vec3f) -> vec2f {
  return p.xz - u.cloudWind * ALTO_SPEED;
}

fn altoWeather(position: vec2f) -> AltoWeather {
  let evolution = 0.02 * u.cloudEvolution;
  let patches = sampleNoise(vec3f(position / ALTO_PATCH_TILE, 0.7 + evolution)).r;
  let edge = 1.0 - u.altocumulusCoverage;
  let cover = saturate(remap(patches, edge - ALTO_PATCH_EDGE, edge + ALTO_PATCH_EDGE, 0.0, 1.0));
  return AltoWeather(cover, ROW_BEND * bend(position, ROW_BEND_TILE, 0.15 + evolution));
}

// Two independent random numbers in [0, 1) and a third for a lattice cell.
fn cellRandom(cell: vec2f) -> vec3f {
  let id = bitcast<vec2u>(vec2i(cell));
  let a = pcg(id.x ^ pcg(id.y));
  let b = pcg(a);
  return vec3f(f32(a & 0xffffu), f32(a >> 16u), f32(b & 0xffffu)) / 65536.0;
}

// The nearest cloudlet around a point of the field: how far the point lies from its centre over
// its radius (< 1 inside it), and in which direction (cells). From the 3 × 3 cells around the
// point; neighbours join smoothly (a polynomial smooth minimum, Quilez) rather than in the creases
// of a Voronoi diagram.
struct Nearest {
  distance: f32,
  heading: vec2f,
}

fn nearestCloudlet(cells: vec2f, radius: f32) -> Nearest {
  let cell = floor(cells);
  let f = cells - cell;
  let churn = TAU * u.cloudEvolution / ALTO_CHURN;
  var nearest = Nearest(2.0, vec2f(1.0, 0.0));
  var closest = 2.0;
  for (var i = 0; i < 9; i++) {
    let offset = vec2f(f32(i % 3 - 1), f32(i / 3 - 1));
    let random = cellRandom(cell + offset);
    let wander = CELL_WANDER * vec2f(sin(churn + TAU * random.x), cos(churn + TAU * random.y));
    let centre = offset + 0.5 + CELL_JITTER * (random.xy - 0.5) + wander;
    let size = min(radius * mix(CLOUDLET_SIZES.x, CLOUDLET_SIZES.y, random.z), CLOUDLET_REACH);
    let away = f - centre;
    let distance = length(away) / size;
    if (distance < closest) {
      closest = distance;
      nearest.heading = away / max(length(away), 1e-6);
    }
    let seam = max(MERGE - abs(distance - nearest.distance), 0.0) / MERGE;
    nearest.distance = min(nearest.distance, distance) - 0.25 * MERGE * seam * seam;
  }
  return nearest;
}

// The cloudlets over a point of the field: domes on a flat base, whose tops reach `tops` of the
// layer's depth, with `density` falling from their cores to nothing at their rims, so they round
// off seen from the side yet fade softly seen from below; and how far (km) the key light travels
// from the point to the rim.
struct Cloudlets {
  tops: f32,
  density: f32,
  toRim: f32,
}

// The cloudlets as a sample standing for `footprint` km sees them, lit along `toLight`. Cells it
// cannot resolve give way to their mean, a veil through the layer's depth as thick as they would
// be on average, and the fray to none.
fn cloudlets(position: vec2f, weather: AltoWeather, footprint: f32, toLight: vec3f) -> Cloudlets {
  let warped = position + weather.warp;
  let flow = warped + CLOUDLET_EDDY * bend(warped, CLOUDLET_EDDY_TILE, 0.55 + 0.1 * u.cloudEvolution);
  let across = vec2f(-SHEAR.y, SHEAR.x);
  let along = dot(flow, SHEAR);
  let billows = 1.0 + BILLOW_SWELL * sin(TAU * along / BILLOW);
  let swell = 1.0 + WAVE_SWELL * sin(TAU * along / WAVE_TRAIN);
  let sharp = resolved(CLOUDLET_SPACING, footprint);
  // The billows only where the cloudlets that show them are resolved: without them, a bare wave.
  let radius = CLOUDLET_RADIUS * sqrt(weather.cover) * mix(1.0, billows, sharp) * swell;
  let nearest = nearestCloudlet(vec2f(along, dot(flow, across)) / CELL, radius);
  var distance = nearest.distance;
  let fine = resolved(FRAY_SPACING, footprint);
  var mottle = 1.0;
  if (fine > 0.0 && distance < 1.0 + 0.5 * ALTO_FRAY) {
    let detail = dot(sampleNoise(vec3f(flow / FRAY_TILE, 0.4 + 0.1 * u.cloudEvolution)).ba, FRAY_WEIGHTS);
    distance += fine * ALTO_FRAY * (0.5 - detail);
    mottle = 1.0 - fine * MOTTLE * (1.0 - detail);
  }
  // A hemisphere's height, and a density thinning to nothing at the rim, less where the field
  // fringes out; together a column as thick as (1 − n²)^1.5, which averages ⅖ over the disk.
  let rim = saturate(1.0 - distance * distance);
  let thickness = mix(0.5, 1.0, weather.cover);
  let mean = 0.4 * thickness * min(PI * radius * radius, 1.0);
  // The light's way to the rim: the cloudlet as a unit disk with the point `distance` out from
  // its centre, and the light crossing it at `light` radii per km.
  let light = vec2f(dot(toLight.xz, SHEAR), dot(toLight.xz, across)) / (CELL * radius);
  let reach = dot(light, light);
  let b = distance * dot(nearest.heading, light);
  let c = distance * distance - 1.0;
  let chord = (sqrt(max(b * b - reach * c, 0.0)) - b) / max(reach, 1e-8);
  let shape = Cloudlets(
    mix(1.0, sqrt(rim), sharp),
    mix(mean, thickness * rim * mottle, sharp),
    mix(ALTO_LIGHT_REACH, min(chord, ALTO_LIGHT_REACH), sharp),
  );
  // Merged into altostratus: a sheet through most of the layer, the cells a texture on it.
  let sheet = u.altocumulusSheet;
  return Cloudlets(
    mix(shape.tops, 0.6 + 0.4 * shape.tops, sheet),
    mix(shape.density, weather.cover * (0.4 + 0.6 * shape.density), sheet),
    mix(shape.toRim, ALTO_LIGHT_REACH, sheet),
  );
}

// rgb: radiance toward the eye; a: transmittance.
fn altocumulus(dir: vec3f, jitter: f32, lighting: CloudLighting) -> vec4f {
  if (u.altocumulusCoverage <= 0.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  let r = observerRadius();
  let eye = vec3f(0.0, r, 0.0);
  let depth = altoDepth();
  let enter = raySphere(r, dir.y, altoBase()).y;
  let leave = raySphere(r, dir.y, altoBase() + depth).y;
  let middle = 0.5 * (enter + leave);
  let weather = altoWeather(altoSpace(eye + dir * middle));
  if (weather.cover <= 0.0) {
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }
  // A cell's span on the layer, stretched along the view where the ray meets it obliquely.
  let footprint = middle * u.cloudCell * 2.0 * u.tanHalfFov.y / u.resolution.y / max(dir.y, 0.1);
  let cosTheta = dot(dir, lighting.keyDirection);
  let diffusion = 0.75 * (1.0 - FORWARD) * ALTO_EXTINCTION * depth;
  let across = (leave - enter) * length(dir.xz);
  let oblique = clamp(across / ALTO_STRIDE, ALTO_STEPS.x, ALTO_STEPS.y);
  let steps = ceil(mix(ALTO_STEPS.x, oblique, resolved(CLOUDLET_SPACING, footprint)));
  let stepLength = (leave - enter) / steps;

  var radiance = vec3f(0.0);
  var seen = 1.0;
  for (var i = 0.0; i < steps; i += 1.0) {
    let t = enter + i * stepLength;
    let low = altoHeight(eye + dir * t);
    let high = altoHeight(eye + dir * (t + stepLength));
    let shape = cloudlets(altoSpace(eye + dir * (t + jitter * stepLength)), weather, footprint, lighting.keyDirection);
    // The share of the step below the tops, with the height taken to run linearly along it.
    let inCloud = saturate((shape.tops - low) / max(high - low, 1e-4));
    if (inCloud <= 0.0 || shape.density <= 0.0) {
      continue;
    }
    let opticalDepth = ALTO_EXTINCTION * shape.density * inCloud * stepLength;
    let lit = t + inCloud * stepLength * meanScatteringDepth(opticalDepth);
    let q = eye + dir * lit;
    let h = saturate(altoHeight(q));
    // The light's way out: to the rim, or through the top or the base, whichever comes first.
    let up = lighting.keyDirection.y;
    let outOfLayer = select(h, shape.tops - h, up > 0.0) * depth / max(abs(up), 1e-3);
    let lightDepth = ALTO_EXTINCTION * WAY_OUT * shape.density * min(shape.toRim, outOfLayer);
    let keyLight = lighting.keyIlluminance * transmittanceAt(q, lighting.keyDirection);
    let direct = keyLight * scattering(lightDepth, cosTheta, OCTAVE_REACH);
    // Skylight through the cloudlet above the sample and grass light through the one below.
    let reach = 1.0 / (1.0 + diffusion * shape.density * vec2f(max(shape.tops - h, 0.0), h));
    let sky = mix(lighting.sky, lighting.shadedSky, 1.0 - exp(-lightDepth / SHADE_DEPTH));
    let ambient = mix(mix(lighting.ground * reach.y, sky * reach.x, 0.7), sky, SIDE_SKYLIGHT);
    let opacity = 1.0 - exp(-opticalDepth);
    radiance += seen * opacity * (direct + ambient);
    seen *= 1.0 - opacity;
  }
  return throughAir(vec4f(radiance, seen), dir, middle);
}
