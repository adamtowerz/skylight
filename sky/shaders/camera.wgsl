// The camera as the shaders see it. Everything in view (air, clouds, stars) is effectively at
// infinity from a camera that only turns, so a pixel is just a direction, and where something was
// on screen last frame is that same direction seen through last frame's camera.

// World-space view ray through a point of the screen, in normalised device coordinates.
fn rayThrough(ndc: vec2f) -> vec3f {
  let ray = u.cameraForward + ndc.x * u.tanHalfFov.x * u.cameraRight + ndc.y * u.tanHalfFov.y * u.cameraUp;
  return normalize(ray);
}

// Normalised device coordinates of a pixel on a target of the given size.
fn pixelNdc(pixel: vec2f, size: vec2f) -> vec2f {
  return vec2f(pixel.x / size.x * 2.0 - 1.0, 1.0 - pixel.y / size.y * 2.0);
}

// World-space view ray through a pixel of the scene target.
fn viewRay(pixel: vec2f) -> vec3f {
  return rayThrough(pixelNdc(pixel, u.resolution));
}

// Where direction `dir` falls on the screen now: xy its normalised device coordinates, z its
// depth along the view (≤ 0 behind the camera).
fn screenPoint(dir: vec3f) -> vec3f {
  let depth = dot(dir, u.cameraForward);
  return vec3f(vec2f(dot(dir, u.cameraRight), dot(dir, u.cameraUp)) / (depth * u.tanHalfFov), depth);
}

// Where direction `dir` fell on the previous frame, as a uv over the scene target (outside
// [0, 1]² if it was out of view).
fn previousUv(dir: vec3f) -> vec2f {
  let depth = dot(dir, u.previousCameraForward);
  let ndc = vec2f(dot(dir, u.previousCameraRight), dot(dir, u.previousCameraUp)) / (depth * u.tanHalfFov);
  return select(vec2f(-1.0), vec2f(0.5 + 0.5 * ndc.x, 0.5 - 0.5 * ndc.y), depth > 0.0);
}
