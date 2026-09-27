// Sky-view LUT (Hillaire 2020): the atmosphere's radiance around the observer, per unit of a
// light's illuminance, parametrised relative to that light (see `skyViewUnit`). Layer 0 is lit
// by the sun, layer 1 by the moon: the same physics, so moonlit night is Rayleigh-blue too.
// Single scattering with shadowed sunlight, plus ψ_ms for every higher order.

@group(0) @binding(5) var skyView: texture_storage_2d_array<rgba16float, write>;

// Steps are spaced quadratically, dense near the observer where the air is thickest.
const STEPS = 32;

// Radiance reaching the observer along a view ray (zenith cosine mu, cosine nu with the light).
fn inScattering(r: f32, mu: f32, muLight: f32, nu: f32) -> vec3f {
  let ground = hitsGround(r, mu);
  let rayLength = select(raySphere(r, mu, u.topRadius).y, raySphere(r, mu, u.bottomRadius).x, ground);
  let rayleigh = rayleighPhase(nu);
  let mie = miePhase(nu);

  var throughput = vec3f(1.0);
  var radiance = vec3f(0.0);
  var t0 = 0.0;
  for (var i = 1; i <= STEPS; i++) {
    let s = f32(i) / f32(STEPS);
    let t1 = rayLength * s * s;
    let dt = t1 - t0;
    let t = 0.5 * (t0 + t1);
    t0 = t1;

    let rt = radiusAlong(r, mu, t);
    let muLightT = muAlong(r, muLight, nu, t, rt);
    let m = medium(rt - u.bottomRadius);
    let scattered = transmittance(rt, muLightT) * (m.rayleighScattering * rayleigh + m.mieScattering * mie)
      + multiscattering(rt, muLightT) * (m.rayleighScattering + m.mieScattering);

    // Hillaire's energy-conserving step: ∫ S e^(−σt·t) dt over the step, analytically.
    let stepTransmittance = exp(-m.extinction * dt);
    radiance += throughput * scattered * (1.0 - stepTransmittance) / max(m.extinction, vec3f(1e-9));
    throughput *= stepTransmittance;
  }
  return radiance;
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let size = textureDimensions(skyView);
  if (any(id.xy >= size)) {
    return;
  }
  let light = select(u.sunDirection, u.moonDirection, id.z == MOON_LAYER);

  // Inverse of `skyViewUnit`, in a frame where the light lies in the xy plane.
  let unit = texelToUnit(id.xy, size);
  let azimuth = unit.x * PI;
  let elevation = unit.y * unit.y * 0.5 * PI;
  let view = vec3f(cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth));
  let nu = dot(view, vec3f(length(light.xz), light.y, 0.0));

  let radiance = inScattering(observerRadius(), view.y, light.y, nu);
  textureStore(skyView, id.xy, id.z, vec4f(radiance, 1.0));
}
