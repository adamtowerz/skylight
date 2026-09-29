@AGENTS.md

# Skylight

The sky as seen lying on the grass, looking up: a static Next.js 16 page (`app/`, one client
component `components/sky.tsx`) that lazily imports a framework-free WebGPU engine (`sky/`).
Physically based atmosphere (Hillaire 2020 LUTs) and raymarched clouds with temporal
accumulation, finished with AgX, grade, paper, grain and dither. `README.md` explains the
rendering; `.context/SPEC.md` (gitignored) is the detailed spec, when present.

## Map

- `sky/index.ts` `start(canvas)`: per frame the CPU advances `clock.ts`, places sun/moon
  (`celestial.ts`) and camera (`camera.ts`), picks the mood (`moods.ts`), fills the uniforms and
  calls `renderer.render`.
- `sky/renderer.ts` owns every shared GPU resource (uniform and exposure buffers, LUTs, noise
  volume, cloud shadow map, shaft and cloud layers, history pair, scene target) and encodes the
  frame graph in order:
  noise (once) → transmittance → multiscattering → sky view → exposure → cloud shadow (Beer
  shadow map of the cumulus along the key light, `keylight.wgsl`) → light shafts (beams of
  sunlight through the gaps, one pixel per 2 × 2 cell) → shaft mean (their average lit share) →
  cloud layer (one pixel per 2 × 2 cell, `interleave.ts`) → scene (sky plus lane contrast, clouds
  rebuilt and averaged over frames) → post (swap chain).
- `sky/passes/*.ts` one per pass: pipeline + bind groups only. `sky/shaders/*.wgsl` the shaders.
- `sky/uniforms.ts` the one `Uniforms` schema; `struct.ts` generates both the WGSL struct and the
  typed TS writer from it, so offsets can't disagree. Add a uniform there and nowhere else.
- `sky/edges.ts` reads back the output's top/bottom row colours a few times a second so the
  page around the canvas can match the sky under iOS Safari's bars (`components/sky.tsx`).

## Conventions

- Small files, one idea each; names that read like the physics; a doc comment at the top of each
  module/shader saying *why* (and citing the technique). No dead code, no commented-out
  experiments, no unused exports, no `any`. TS constants camelCase, WGSL constants SCREAMING_CASE.
- WGSL has no imports: modules are composed by concatenation, `shader(device, label, [uniformsWgsl, common, …])`.
- Passes use `layout: 'auto'`, which drops unused bindings: bind only what the shader reads.
- Art direction amplifies physical parameters (moods), never paints colour on top.
- The page must stay static (`○` in `next build`); no runtime deps beyond next/react.

## Controls

`?hour=18.8` start hour (without it, a random opening moment from `sky/seeds.ts`; `?seed=n`
picks one) · `?speed=0` freeze the clock · `?mood=0..4` (goldenHaze, violetDusk, emberSky,
clear, softOvercast) · scroll/drag scrubs time · ←/→ ±15 min · space pause. Sunset is
18:52; golden hour ≈ 18.0–18.8; afterglow 18.9–19.4; blue hour 19.3–19.8.

## Gotchas

- `.wgsl` imports go through `scripts/wgsl-loader.cjs`: Turbopack's built-in `{ type: 'raw' }`
  yields an empty module in Next 16.3.
- `next start` leaves a `next-server` child listening after its parent dies. Kill by port and
  confirm it's free before restarting, or you will screenshot a stale build. Use private ports
  (3417, baseline 3418); leave other ports alone.
- Screenshots need ~6 s for the reveal, TAA and exposure to settle.
- `.context/` is gitignored scratch: screenshots, sheets, notes.
- Work happens on `main`; every push to `main` deploys production at www.skylight.sh. Don't push
  experiments without the user's approval (see the `deploy` skill).

## Seeing the result

Visual changes are verified by looking: the `render-review` skill has the loop (build, serve,
`scripts/shots.mjs` matrix, `scripts/sheet.mjs` before/after sheets, `scripts/baseline.sh`,
`scripts/frametime.mjs`) and a checklist of failure modes.
