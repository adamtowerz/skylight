// A plane-parallel slab of cloud droplets, solved in closed form: what the fog the eye lies in
// (fog.wgsl) and the deck overhead (deck.wgsl) share. Droplets far larger than light's
// wavelengths scatter every colour alike and barely absorb, so a slab of them is grey and
// conservative: what it does not reflect it transmits, direct or diffuse. How much it reflects
// is the two-stream (Eddington) solution (Shettle & Weinman 1970; Bohren 1987, "Multiple
// scattering of light and some of its observable consequences"). Where the diffuse light seems to
// come from broadens with every scattering: the droplets' forward phase (g ≈ 0.85) raised to the
// number of scatterings a ray has suffered, so a thin mist glows around the sun and a thick bank
// or deck is evenly luminous.

// Mean cosine of scattering by cloud droplets in visible light.
const DROPLET_ANISOTROPY = 0.85;
// Half of what a droplet takes out of a beam it only diffracts, into a cone a few degrees wide
// (the extinction paradox): the phase of light scattered by diffraction alone.
const DIFFRACTION = 0.96;

// Eddington's reflectance of a conservative slab of optical depth `tau` lit from zenith cosine
// `mu`.
fn slabReflectance(tau: f32, mu: f32) -> f32 {
  let diffusion = 0.75 * (1.0 - DROPLET_ANISOTROPY) * tau;
  return (diffusion + (0.5 - 0.75 * mu) * (1.0 - exp(-tau / mu))) / (1.0 + diffusion);
}

// The share of a light arriving at zenith cosine `mu` that a slab of optical depth `tau` only
// diffracts: it keeps close to the light's direction, its soft disc and aureole.
fn slabDiffracted(tau: f32, mu: f32) -> f32 {
  return exp(-0.5 * tau / mu) - exp(-tau / mu);
}

// Radiance of the light a light of illuminance `illuminance` (on the slab's top, from `light`,
// arriving at zenith cosine `mu`) sends down out of a slab of optical depth `tau` along `dir`, less
// what it lets through unscattered. `diffuseWeight` scales the diffuse part by how much of it
// comes from `dir`: 1 on average over the lower hemisphere.
fn slabGlow(dir: vec3f, light: vec3f, mu: f32, illuminance: vec3f, tau: f32, diffuseWeight: f32) -> vec3f {
  let direct = exp(-tau / mu);
  let cosTheta = dot(dir, light);
  let diffracted = slabDiffracted(tau, mu);
  // The rest is diffuse, and each scattering blurs its forward peak further; its phase is
  // normalised over the lower hemisphere as it goes from the light's direction (g → 1) to
  // uniform (g → 0).
  let diffuse = max(1.0 - slabReflectance(tau, mu) - direct - diffracted, 0.0);
  let g = pow(DROPLET_ANISOTROPY, 1.0 + tau / mu);
  let hemisphere = 0.25 * (1.0 - g) + g * mu;
  return illuminance * (diffracted * henyeyGreenstein(cosTheta, DIFFRACTION)
    + diffuseWeight * mu * diffuse * henyeyGreenstein(cosTheta, g) / hemisphere);
}
