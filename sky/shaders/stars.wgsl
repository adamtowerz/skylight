// Every star as it is seen this frame (`seeStar`: where it falls, its colour, twinkle and flux,
// what the air and the clouds let through), worked out once per star rather than once per pixel
// it lights, so that `post` only spreads each one's light over its pixels. One invocation per
// slot of `seenstars.wgsl`: the catalogue's stars, then the faint field's cells.

@group(0) @binding(6) var scene: texture_2d<f32>; // a: the view to space
@group(0) @binding(7) var sceneSampler: sampler;
@group(0) @binding(8) var<storage, read> catalogue: array<Star>;
@group(0) @binding(9) var<storage, read_write> seenStars: array<SeenStar>;

fn seeCatalogueStar(index: u32) -> SeenStar {
  let star = catalogue[index];
  var seen = seeStar(star, hash3(bitcast<vec3u>(star.direction)));
  seen.light *= throughSky(seen.centre, toLocal(star.direction));
  return seen;
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3u) {
  let slot = id.x;
  if (slot >= arrayLength(&seenStars)) {
    return;
  }
  if (slot < CATALOGUE_STARS) {
    seenStars[slot] = seeCatalogueStar(slot);
    return;
  }
  let cell = slot - CATALOGUE_STARS;
  let row = cell / FIELD_CELLS;
  seenStars[slot] = seeFaintStar(row / FIELD_CELLS, vec2u(cell % FIELD_CELLS, row % FIELD_CELLS));
}
