// The frames the sky beyond the air is described in. Local: x = east, y = up, z = north. J2000
// equatorial: x toward RA 0h, z the celestial pole; it turns with the Earth (`skyRotation`, from
// `sky/celestial.ts`). Galactic coordinates are `galactic.wgsl`'s.

fn skyRotationMatrix() -> mat3x3f {
  return mat3x3f(u.skyRotation[0].xyz, u.skyRotation[1].xyz, u.skyRotation[2].xyz);
}

fn toEquatorial(dir: vec3f) -> vec3f {
  return dir * skyRotationMatrix();
}

fn toLocal(equatorial: vec3f) -> vec3f {
  return skyRotationMatrix() * equatorial;
}
