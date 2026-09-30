// Galactic coordinates: where the Milky Way lies and faint stars crowd toward it. The rotation
// from J2000 equatorial is Hipparcos's (ESA 1997, vol. 1 §1.5.3), its columns here the galactic
// centre (l = 0, b = 0), l = 90° and the north galactic pole (RA 192.86°, Dec 27.13°).

const GALACTIC_AXES = mat3x3f(
  -0.0548755604, -0.8734370902, -0.4838350155,
  0.4941094279, -0.4448296300, 0.7469822445,
  -0.8676661490, -0.1980763734, 0.4559837762,
);

// x toward the galactic centre, z toward the north galactic pole.
fn toGalactic(equatorial: vec3f) -> vec3f {
  return equatorial * GALACTIC_AXES;
}
