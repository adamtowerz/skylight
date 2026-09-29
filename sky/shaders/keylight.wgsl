// The key light: the one light that shapes the clouds and casts their shadows. It is the sun until
// the sun no longer reaches even the cirrus, then the moon, faded in across twilight so that the
// switch never shows: by the time the direction jumps, neither light is lighting anything.

// sin(−3.5°): below this the sun no longer reaches even the cirrus (an 8 km horizon dips ≈ 2.9°,
// plus the soft band), and the moon takes over as the key light.
const SUN_REACH = -0.061;
// sin(−7°): by here moonlight is fully in.
const MOONLIGHT = -0.122;

struct KeyLight {
  direction: vec3f,
  illuminance: vec3f, // above the atmosphere
}

// How far moonlight has taken over from sunlight, 0 → 1 through twilight.
fn moonlight() -> f32 {
  return smoothstep(SUN_REACH, MOONLIGHT, u.sunDirection.y);
}

fn keyLight() -> KeyLight {
  if (u.sunDirection.y > SUN_REACH) {
    return KeyLight(u.sunDirection, u.sunIlluminance);
  }
  return KeyLight(u.moonDirection, u.moonIlluminance * moonlight());
}
