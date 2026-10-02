// From HDR radiance to the screen, in the order light meets film and paper:
// stars → rain → drops on the eye → exposure → vignette → AgX tonemap → grade → paper → grain → soft quantization,
// then the eyes-opening reveal from the blank colour. The goal is emotion, not a photograph.
// The stars and the rain join the upsampled scene here, at the display's own pixels
// (`starfield.wgsl`, `rain.wgsl`), and the drops on the eye refract it (`eyedrop.wgsl`).

@group(0) @binding(1) var<storage, read> exposure: Exposure;
@group(0) @binding(2) var scene: texture_2d<f32>;
@group(0) @binding(3) var sceneSampler: sampler;

const GRAIN_FPS = 12.0;
// Width of the opening's soft edge, as a fraction of the centre-to-corner distance.
const REVEAL_SOFTNESS = 0.6;
// Exposure multipliers as the eyes first open, out of a dark or a light page; both ramp to 1 with
// the reveal, so the sky emerges from the blank's brightness rather than cutting against it.
const REVEAL_DARKNESS = 0.25;
const REVEAL_GLARE = 6.0;

// AgX (Troy Sobotka), minimal fit by Benjamin Wrensch (2023): an inset gamut, a log2 encoding
// over a fixed EV range, a sigmoid polynomial, then the outset. The result is already display
// encoded (≈ 2.2 gamma), which is exactly what a unorm swap chain wants.
const AGX_INSET = mat3x3f(
  0.842479062253094, 0.0423282422610123, 0.0423756549057051,
  0.0784335999999992, 0.878468636469772, 0.0784336,
  0.0792237451477643, 0.0791661274605434, 0.879142973793104,
);
const AGX_OUTSET = mat3x3f(
  1.19687900512017, -0.0528968517574562, -0.0529716355144438,
  -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
  -0.0990297440797205, -0.0989611768448433, 1.15107367264116,
);
const AGX_MIN_EV = -12.47393;
const AGX_MAX_EV = 4.026069;

fn agxContrast(x: vec3f) -> vec3f {
  let x2 = x * x;
  let x4 = x2 * x2;
  return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}

fn agx(radiance: vec3f) -> vec3f {
  let ev = clamp(log2(max(AGX_INSET * radiance, vec3f(1e-10))), vec3f(AGX_MIN_EV), vec3f(AGX_MAX_EV));
  let curve = agxContrast((ev - AGX_MIN_EV) / (AGX_MAX_EV - AGX_MIN_EV));
  return saturate(AGX_OUTSET * curve);
}

// A gentle grade: a little more colour, cool blue shadows, warm highlights.
fn grade(color: vec3f) -> vec3f {
  let l = luminance(color);
  let saturated = mix(vec3f(l), color, 1.4);
  let tint = mix(vec3f(0.97, 0.99, 1.05), vec3f(1.03, 1.0, 0.96), smoothstep(0.15, 0.8, l));
  return saturate(saturated * tint);
}

// Lens falloff toward the corners; `r` is 0 at the centre and 1 in the corners.
fn vignette(r: f32) -> f32 {
  return 1.0 - u.vignette * smoothstep(0.3, 1.0, r);
}

fn valueNoise(p: vec2f) -> f32 {
  let cell = bitcast<vec2u>(vec2i(floor(p)));
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let bottom = mix(hash2(cell), hash2(cell + vec2u(1u, 0u)), w.x);
  let top = mix(hash2(cell + vec2u(0u, 1u)), hash2(cell + vec2u(1u, 1u)), w.x);
  return mix(bottom, top, w.y);
}

// Paper: a faint multiplicative tooth of crossed fibres, fixed to the screen like a print.
fn paper(pixel: vec2f) -> f32 {
  let p = pixel / u.outputResolution.y * 900.0;
  let fibres = 0.5 * valueNoise(p * vec2f(0.35, 1.6))
    + 0.3 * valueNoise(p * vec2f(1.7, 0.4) + 17.0)
    + 0.2 * valueNoise(p * 3.1 + 41.0);
  return 1.0 + u.paper * (fibres - 0.5) * 2.0;
}

// Film grain refreshed at a low frame rate, like projected film. Triangular noise in (−1, 1).
fn grain(pixel: vec2f) -> f32 {
  let frame = u32(u.time * GRAIN_FPS);
  let p = vec2u(pixel);
  return hash3(vec3u(p, frame)) + hash3(vec3u(p, frame + 7919u)) - 1.0;
}

// Soft quantization: step toward `ditherLevels` levels through blue-ish noise, then keep only
// half the step, for a faint printed texture that never bands.
fn quantize(color: vec3f, pixel: vec2f) -> vec3f {
  let noise = interleavedGradientNoise(pixel) - 0.5;
  let stepped = floor(color * u.ditherLevels + 0.5 + noise) / u.ditherLevels;
  return mix(color, stepped, 0.5);
}

// Eyes opening: a soft-edged opening grows from the centre. Exactly 0 everywhere at reveal = 0.
fn opening(r: f32) -> f32 {
  let edge = u.reveal * (1.0 + REVEAL_SOFTNESS);
  return smoothstep(0.0, 1.0, saturate((edge - r) / REVEAL_SOFTNESS));
}

@fragment
fn main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let pixel = position.xy;
  let uv = pixel / u.outputResolution;
  let aspect = vec2f(u.outputResolution.x / u.outputResolution.y, 1.0);
  let r = length((uv - 0.5) * aspect) / length(0.5 * aspect);

  let sky = textureSample(scene, sceneSampler, uv).rgb;
  let hdr = eyeDrops(pixel, rain(pixel, sky + stars(pixel, sky)));
  let firstLight = mix(REVEAL_DARKNESS, REVEAL_GLARE, luminance(u.blankColor));
  let eyes = mix(firstLight, 1.0, u.reveal);
  let exposed = hdr * exposure.value * exp2(u.exposureBias) * eyes * vignette(r);

  var color = grade(agx(exposed)) * paper(pixel);
  let midtones = mix(0.35, 1.0, 4.0 * luminance(color) * (1.0 - luminance(color)));
  color = saturate(color + u.grain * midtones * grain(pixel));
  color = quantize(color, pixel);

  // Mixing last keeps grain and dither out of the blank: at reveal = 0 this is blankColor.
  return vec4f(mix(u.blankColor, color, opening(r)), 1.0);
}
