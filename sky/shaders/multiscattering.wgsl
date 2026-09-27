// Multiscattering LUT (Hillaire 2020): light scattered more than once, as a function of altitude
// and the light's zenith cosine. One workgroup per texel; each of its 64 threads marches one
// direction of a stratified uniform sphere, gathering second-order radiance L₂ (isotropic phase,
// plus the sunlit ground) and the transfer factor f_ms, the fraction re-scattered toward the
// point. Summing the geometric series of bounces gives ψ_ms = L₂ / (1 − f_ms).

@group(0) @binding(5) var lut: texture_storage_2d<rgba16float, write>;

const SQRT_DIRECTIONS = 8u;
const DIRECTIONS = 64u;
const STEPS = 20;
const ISOTROPIC_PHASE = 1.0 / (4.0 * PI);

var<workgroup> secondOrder: array<vec3f, DIRECTIONS>;
var<workgroup> transfer: array<vec3f, DIRECTIONS>;

struct Gathered {
  secondOrder: vec3f,
  transfer: vec3f,
}

// Marches one direction (zenith cosine mu, cosine nu with the light) from radius r to the ground
// or space, accumulating each step's in-scattering analytically (Hillaire's energy-conserving
// ∫ e^(−σt·t) dt = (1 − e^(−σt·Δt)) / σt).
fn march(r: f32, mu: f32, muLight: f32, nu: f32) -> Gathered {
  let ground = hitsGround(r, mu);
  let rayLength = select(raySphere(r, mu, u.topRadius).y, raySphere(r, mu, u.bottomRadius).x, ground);
  let dt = rayLength / f32(STEPS);

  var throughput = vec3f(1.0);
  var light = vec3f(0.0);
  var transferred = vec3f(0.0);
  for (var i = 0; i < STEPS; i++) {
    let t = (f32(i) + 0.5) * dt;
    let rt = radiusAlong(r, mu, t);
    let m = medium(rt - u.bottomRadius);
    let scattering = m.rayleighScattering + m.mieScattering;
    let stepTransmittance = exp(-m.extinction * dt);
    let integral = throughput * (1.0 - stepTransmittance) / max(m.extinction, vec3f(1e-9));
    let lit = transmittance(rt, muAlong(r, muLight, nu, t, rt));
    light += integral * scattering * lit * ISOTROPIC_PHASE;
    transferred += integral * scattering;
    throughput *= stepTransmittance;
  }

  // Sunlight bounced off a Lambertian ground.
  if (ground) {
    let muGround = muAlong(r, muLight, nu, rayLength, u.bottomRadius);
    light += throughput * transmittance(u.bottomRadius, muGround) * saturate(muGround) * u.groundAlbedo / PI;
  }

  return Gathered(light, transferred);
}

@compute @workgroup_size(DIRECTIONS)
fn main(@builtin(workgroup_id) texel: vec3u, @builtin(local_invocation_index) index: u32) {
  let unit = texelToUnit(texel.xy, textureDimensions(lut));
  let muLight = unit.x * 2.0 - 1.0;
  // Just inside the shell, so no ray starts on its boundary.
  let r = mix(u.bottomRadius + 0.01, u.topRadius - 0.01, unit.y);

  // Stratified uniform sphere: even steps in azimuth φ and in cos θ.
  let phi = TAU * (f32(index % SQRT_DIRECTIONS) + 0.5) / f32(SQRT_DIRECTIONS);
  let mu = 1.0 - 2.0 * (f32(index / SQRT_DIRECTIONS) + 0.5) / f32(SQRT_DIRECTIONS);
  let nu = sqrt(1.0 - mu * mu) * cos(phi) * sqrt(1.0 - muLight * muLight) + mu * muLight;
  let gathered = march(r, mu, muLight, nu);
  secondOrder[index] = gathered.secondOrder / f32(DIRECTIONS);
  transfer[index] = gathered.transfer / f32(DIRECTIONS);

  for (var stride = DIRECTIONS / 2u; stride > 0u; stride >>= 1u) {
    workgroupBarrier();
    if (index < stride) {
      secondOrder[index] += secondOrder[index + stride];
      transfer[index] += transfer[index + stride];
    }
  }
  if (index == 0u) {
    let psi = secondOrder[0] / max(1.0 - transfer[0], vec3f(1e-3));
    textureStore(lut, texel.xy, vec4f(psi, 1.0));
  }
}
