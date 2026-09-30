// The starlight on each display pixel, from the stars as the `stars` pass saw them this frame.
// The bright ones are the real sky's: the Yale Bright Star Catalogue down to V = 5.5
// (`sky/brightstars.ts`), binned by `sky/catalogue.ts` into the cells of a cube map, each cell
// listing every star whose light can reach it, so a pixel looks only at its own cell's few. The
// faint field (`faintstars.wgsl`) holds at most one star per cell of a finer cube map, whose
// light reaches less than half a cell, so a pixel looks only at the 2 × 2 cells nearest it.

@group(0) @binding(4) var<storage, read> catalogueCells: array<u32>; // each cell's first entry, then one past the last
@group(0) @binding(5) var<storage, read> catalogueEntries: array<u32>; // stars, by index, cell after cell
@group(0) @binding(6) var<storage, read> seenStars: array<SeenStar>;

fn catalogueStars(pixel: vec2f, point: CubePoint) -> vec3f {
  let cell = cubeCellIndex(point.face, min(vec2u(point.uv * f32(CATALOGUE_CELLS)), vec2u(CATALOGUE_CELLS - 1u)), CATALOGUE_CELLS);
  var light = vec3f(0.0);
  for (var i = catalogueCells[cell]; i < catalogueCells[cell + 1u]; i++) {
    light += starlight(pixel, seenStars[catalogueEntries[i]]);
  }
  return light;
}

fn faintStars(pixel: vec2f, point: CubePoint) -> vec3f {
  let nearest = vec2i(round(point.uv * f32(FIELD_CELLS)));
  var light = vec3f(0.0);
  for (var i = 0; i < 4; i++) {
    let cell = nearest - vec2i(i & 1, i >> 1);
    if (all(cell >= vec2i(0)) && all(cell < vec2i(i32(FIELD_CELLS)))) {
      light += starlight(pixel, seenStars[faintSlot(point.face, vec2u(cell))]);
    }
  }
  return light;
}

// All the starlight reaching the display pixel centred at `pixel`, where the scene is `sky`. By
// day even the brightest star (Sirius, V = −1.46) is lost in the sky, and none is looked for.
fn stars(pixel: vec2f, sky: vec3f) -> vec3f {
  if (STAR_FLUX * pow(10.0, 0.4 * 1.46) / pow(displayPixelAngle(), 2.0) < 1e-3 * luminance(sky)) {
    return vec3f(0.0);
  }
  let point = cubePoint(toEquatorial(rayThrough(pixelNdc(pixel, u.outputResolution))));
  return catalogueStars(pixel, point) + faintStars(pixel, point);
}
