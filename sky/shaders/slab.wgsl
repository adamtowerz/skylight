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

// What a droplet absorbs of the light it meets: next to nothing, but water takes out red far more
// than blue (its absorption about 0.45, 0.06 and 0.007 m⁻¹ at 680, 550 and 440 nm; Pope & Fry
// 1997), and a droplet about 10 µm in radius holds light along some 20 µm of water per
// encounter, which with an extinction efficiency of 2 leaves this co-albedo.
const DROPLET_COALBEDO = vec3f(4.5e-6, 6e-7, 7e-8);

// The share of the light diffusing through a slab of optical depth `tau` that its water does not
// absorb. Diffusion attenuates as exp(−kτ), k = √(3(1 − ω)(1 − g)), so through a slab it is
// kτ / sinh kτ of what a conservative one lets by: nothing to a rainy day's deck, but under a
// storm whose tower is many hundreds deep, light that has scattered tens of thousands of times
// loses a share of its red, and the base reads slate blue-grey (Bohren 1987; Bohren & Fraser
// 1993, "The green thunderstorm").
fn slabUnabsorbed(tau: f32) -> vec3f {
  let k = max(sqrt(3.0 * (1.0 - DROPLET_ANISOTROPY) * DROPLET_COALBEDO) * tau, vec3f(1e-4));
  return k / sinh(k);
}

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
