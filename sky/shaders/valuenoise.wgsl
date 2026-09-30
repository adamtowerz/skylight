// Value noise in 3D (smoothstep-interpolated random lattice values, in [0, 1]): cheap, soft
// texture for the moon's maria and the Milky Way's star clouds and dust.

fn valueNoise(p: vec3f) -> f32 {
  let cell = bitcast<vec3u>(vec3i(floor(p)));
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let x00 = mix(hash3(cell), hash3(cell + vec3u(1u, 0u, 0u)), w.x);
  let x10 = mix(hash3(cell + vec3u(0u, 1u, 0u)), hash3(cell + vec3u(1u, 1u, 0u)), w.x);
  let x01 = mix(hash3(cell + vec3u(0u, 0u, 1u)), hash3(cell + vec3u(1u, 0u, 1u)), w.x);
  let x11 = mix(hash3(cell + vec3u(0u, 1u, 1u)), hash3(cell + vec3u(1u, 1u, 1u)), w.x);
  return mix(mix(x00, x10, w.y), mix(x01, x11, w.y), w.z);
}
