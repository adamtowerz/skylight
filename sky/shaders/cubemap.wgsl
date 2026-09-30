// The celestial sphere tiled as a cube map, so the stars can be found by cell: the catalogue's
// bright stars are binned into its cells on the CPU (`sky/stars.ts` mirrors `cubePoint`), and the
// procedural field keeps at most one faint star per cell. The face coordinates are warped by
// atan (an equi-angular cube map, as in Google's 2017 EAC projection), so every cell spans about
// the same angle and none bunch up toward the face corners.

struct CubePoint {
  face: u32, // 2 × major axis, + 1 if it points down that axis
  uv: vec2f, // [0, 1]² across the face, uniform in angle
}

fn cubePoint(dir: vec3f) -> CubePoint {
  let a = abs(dir);
  var axis = 2u;
  if (a.x >= a.y && a.x >= a.z) {
    axis = 0u;
  } else if (a.y >= a.z) {
    axis = 1u;
  }
  let major = dir[axis];
  let tangent = vec2f(dir[(axis + 1u) % 3u], dir[(axis + 2u) % 3u]) / abs(major);
  return CubePoint(2u * axis + select(0u, 1u, major < 0.0), atan(tangent) / (0.5 * PI) + 0.5);
}

fn cubeDirection(point: CubePoint) -> vec3f {
  let axis = point.face / 2u;
  let tangent = tan((point.uv - 0.5) * 0.5 * PI);
  var dir: vec3f;
  dir[axis] = select(1.0, -1.0, (point.face & 1u) == 1u);
  dir[(axis + 1u) % 3u] = tangent.x;
  dir[(axis + 2u) % 3u] = tangent.y;
  return normalize(dir);
}

// Index of a cell among all six faces' `cells` × `cells`, face after face, row after row.
fn cubeCellIndex(face: u32, cell: vec2u, cells: u32) -> u32 {
  return (face * cells + cell.y) * cells + cell.x;
}
