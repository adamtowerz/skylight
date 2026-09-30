// The Milky Way: the unresolved light of the Galaxy's disk, a soft band along the galactic
// equator, thickest and brightest toward the bulge in Sagittarius, swelling again in the star
// clouds of Cygnus, faint toward the anticentre, mottled into clouds and split by the dark dust
// of the Great Rift, which runs just north of the plane from Cygnus to Ophiuchus. Its surface
// brightness is about that of a dark sky's own airglow, so it shows only on the darkest nights,
// and the moonlit sky's added glow washes it out as it would the eye's. It never changes, so it
// is drawn once at init into an equirectangular map of the equatorial sphere, which the scene
// samples behind the air; the fine grain of faint stars crowding toward it is `starfield.wgsl`'s.

@group(0) @binding(0) var map: texture_storage_2d<rgba16float, write>;

// Peak radiance, of old, dusty starlight: a faint warm white.
const MILKY_WAY = vec3f(0.0012, 0.00112, 0.00096);
// Half-thickness of the disk and of the bulge (radians of galactic latitude / angular radius).
const DISK_WIDTH = 0.09;
const BULGE_WIDTH = 0.2;
// The Cygnus star clouds (galactic longitude, radians) and their extent along the plane.
const CYGNUS = 1.36;
const CYGNUS_WIDTH = 0.25;
// Dust: the optical depth of its lanes and of the Great Rift, and the Rift's galactic latitude,
// half-width and span in longitude (radians).
const DUST = 1.6;
const RIFT = 2.4;
const RIFT_LATITUDE = 0.03;
const RIFT_WIDTH = 0.05;
const RIFT_SPAN = vec2f(-0.2, 1.45);

// Three octaves of value noise on the celestial sphere, in [0, 1].
fn skyNoise(p: vec3f) -> f32 {
  return 0.5 * valueNoise(p) + 0.3 * valueNoise(2.1 * p + 13.0) + 0.2 * valueNoise(4.3 * p + 29.0);
}

// A Gaussian profile across a band: 1 at its centre line.
fn band(offset: f32, width: f32) -> f32 {
  return exp(-0.5 * offset * offset / (width * width));
}

// Radiance of the Milky Way toward `equatorial`.
fn milkyWay(equatorial: vec3f) -> vec3f {
  let g = toGalactic(equatorial);
  let latitude = asin(clamp(g.z, -1.0, 1.0));
  let longitude = atan2(g.y, g.x);
  let towardCentre = 0.5 + 0.5 * cos(longitude);
  let disk = band(latitude, DISK_WIDTH) * (0.25 + 0.75 * towardCentre * towardCentre + 0.45 * band(longitude - CYGNUS, CYGNUS_WIDTH));
  let bulge = band(length(vec2f(longitude, 1.4 * latitude)), BULGE_WIDTH);
  let clouds = mix(0.45, 1.4, skyNoise(g * 9.0));
  let alongRift = smoothstep(RIFT_SPAN.x - 0.2, RIFT_SPAN.x + 0.2, longitude) * smoothstep(RIFT_SPAN.y + 0.25, RIFT_SPAN.y - 0.25, longitude);
  let rift = band(latitude - RIFT_LATITUDE, RIFT_WIDTH) * alongRift * skyNoise(g * 24.0 + 3.0);
  let lanes = band(latitude, 2.0 * DISK_WIDTH) * smoothstep(0.35, 0.8, skyNoise(g * 16.0 + 7.0));
  let dust = exp(-RIFT * rift - DUST * lanes);
  return MILKY_WAY * (disk + bulge) * clouds * dust;
}

// One texel per invocation: u right ascension from 0h, v declination from +90° down to −90°.
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(map);
  if (any(id.xy >= size)) {
    return;
  }
  let uv = (vec2f(id.xy) + 0.5) / vec2f(size);
  let ra = TAU * uv.x;
  let dec = PI * (0.5 - uv.y);
  let equatorial = vec3f(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec));
  textureStore(map, id.xy, vec4f(milkyWay(equatorial), 1.0));
}
