# Skylight

The sky as you'd see it lying on your back in the grass. A static Next.js page with a WebGPU
engine behind it: the atmosphere and clouds are physically based, the finish is stylized (AgX
tonemap, gentle grade, paper, film grain, dither). Time drifts from sunset through the night and
back again, lingering at dusk and dawn, and no two sunsets look the same.

## How it loads

The page is prerendered as a blank screen, white or black to match the device theme: about 2 KB of gzipped HTML with its CSS
inlined, no fonts, no stylesheet to wait for. After hydration, `components/sky.tsx` lazily imports
the engine (`sky/`, a separate ≈ 74 KB chunk with the shaders and bright stars), which compiles its pipelines
in parallel and then opens onto the scene in-shader, like eyes opening. Without WebGPU, or if the
GPU is lost, a still CSS dusk fades in instead.

On Vercel the page is cached by the CDN until the next deployment (`s-maxage`), and every script
under `/_next/static` is content-hashed and `immutable`.

## How it renders

The CPU only schedules work. Each frame it advances the clock, places the sun, moon and camera,
fills one uniform buffer (`sky/uniforms.ts`, generated from a schema so TypeScript and WGSL agree
on every offset) and encodes the frame graph (`sky/renderer.ts`):

```
pass              reads                                  writes
noise (once)      —                                      cloud noise volume, 128³
milky way (once)  —                                      Milky Way map, equirectangular
transmittance     —                                      transmittance LUT
multiscattering   transmittance                          multiscattering LUT
skyview           transmittance, multiscattering         sky-view LUT (sun layer, moon layer)
exposure          sky view                               exposure buffer
cloud shadow      noise                                  cloud shadow map, seen from the key light
light shafts      transmittance, cloud shadow map        shaft layer, one pixel in 2 × 2
shaft mean        shaft layer                            average lit share, one texel per 128 px
cloud layer       transmittance, sky view, noise         cloud layer (jittered), one pixel in 2 × 2
scene             transmittance, sky view, cloud layer,  scene target (+ view to space) + next
                  cloud history, shaft layer, shaft mean, cloud history
                  Milky Way map
stars             transmittance, scene target, catalogue every star as seen this frame
post              scene target, exposure, seen stars    swap chain
```

| Pass              | Output                          | Does                                                                    |
| ----------------- | ------------------------------- | ----------------------------------------------------------------------- |
| `noise`           | `rgba8unorm` 128³, once         | tileable Perlin–Worley + Worley fBm for the clouds (Schneider 2015)     |
| `milky way`       | `rgba16float` 1024×512, once    | the Milky Way over the equatorial sphere: disk, bulge, star clouds, dust |
| `transmittance`   | `rgba16float` 256×64            | transmittance to space per (r, μ) (Hillaire 2020, Bruneton's mapping)   |
| `multiscattering` | `rgba16float` 32×32             | ψ_ms: every scattering order past the first, 64 directions per texel    |
| `skyview`         | `rgba16float` 192×108, 2 layers | atmosphere radiance around the observer, lit by the sun / by the moon   |
| `exposure`        | storage buffer `{ value: f32 }` | meters the sky-view LUT over the view; compressed key; adapts over time |
| `cloud shadow`    | `rgba16float` 256×256           | Beer shadow map of the cumulus along the key light (Hillaire 2016)      |
| `light shafts`    | `rgba16float`, ¼ of the scene   | beams of sunlight through the gaps between the heaps, and lit share     |
| `shaft mean`      | `rgba16float`, 1 per 128 px     | the lit share averaged over wide blocks, so shafts add only contrast    |
| `cloud layer`     | `rgba16float`, ¼ of the scene   | one ray per 2 × 2 cell → cumulus, altocumulus, cirrus (radiance, T)     |
| `scene`           | `rgba16float` scene + history   | clouds rebuilt + averaged over frames, over the sky, sun, moon, Milky Way |
| `stars`           | storage buffer, 1 per star      | each star's place, colour, twinkle and light through the air and clouds |
| `post`            | swap chain                      | upsample, stars, exposure, vignette, AgX, grade, paper, grain, dither, reveal |

Every pass reads the same `Uniforms` buffer at `@group(0) @binding(0)`. Passes live in
`sky/passes/`, one file each, and own only their pipelines and bind groups; the renderer owns every
resource that flows between them, so the data flow reads top to bottom in `renderer.ts`. The whole
frame takes about 5 ms of GPU time at 1440 × 900 on an Apple M1 Pro, a quarter of it the cloud march.

## The physics

**Air.** The atmosphere follows Hillaire 2020: Rayleigh and Mie scattering, ozone absorption and
a sunlit ground, baked every frame into a transmittance LUT, a multiple-scattering LUT and a
sky-view LUT with one layer per light (the moonlit night is Rayleigh-blue too, over a faint
airglow floor). The LUTs are cheap, so they are rebuilt every frame: *moods* (`sky/moods.ts`)
change the air itself. Each mood is a set of multipliers on Earth's parameters — aerosol density,
height and Ångström exponent, Mie anisotropy, ozone (the violet of the blue hour), the sunlight's
spectral slope — plus cloud cover. Colour comes from amplified physics, never from paint.

**Clouds.** A raymarched cumulus shell at 1.5–3.5 km sits in front of a thin altocumulus layer at
5 km and a cirrus sheet at 8 km (`clouds.wgsl`, `cumulus.wgsl`, `altocumulus.wgsl`, `cirrus.wgsl`). The heaps are built as in Schneider's Nubis: a
weather field sets how much of the sky is cloud and how tall the heaps grow, from fair-weather
puffs to towering congestus at the hearts of its convection cells (`cloudTowers`, per mood); a
height gradient turns Perlin–Worley heaps into domes whose own cores push their tops up, and the
weather shears them about so every outline is its own; the condensation level cuts every base
flat; broad Worley turrets swell the flanks and tops into one merged body, and finer Worley
detail frays the edges, wispy below and billowy above, both held close to the heaps' own
bodies so that they lobe coherent heaps rather than scatter flecks. Each lookup (the view ray's pixel
cells, the light march's lengthening steps, the shadow map's long ones) resolves only the features
its sample can, so none alias into sparkle as the heaps drift. Density rises from a crisp,
translucent rim into a core as dense as real cumulus, so heaps keep soft volume yet darken their
own bases and crevices. A heap turns opaque within far less than a step of
the view ray, so between two samples the march takes the field to run linearly and integrates the
cloud's sharp threshold along the step exactly, and lights each step where the light it sends to
the eye comes from on average (near the front of a thick step): heap edges move smoothly across
the steps instead of falling into contour lines, at no extra samples. Sunlight reaches every sample through the transmittance LUT, so after the sun sets at
the ground the clouds keep catching it, gold, then rose, then the altocumulus and cirrus alone glow pink. Direct
light uses a short light march, a dual-lobe phase function (the silver lining) and
multiple-scattering octaves after Wrenninge et al. 2013, which reach deeper under a grazing sun so
sunset heaps glow through. Ambient light is the sky-view LUT, with shaded sides seeing only the half
of the sky turned from the sun (blue shadows at noon, violet at dusk), and grass bounce from below,
both dimmed with depth into the heap. At night the moon lights them, and they stand dark against the
airglow with silver rims.

**Mackerel sky.** Now and then a layer of altocumulus a few hundred metres deep lies between
them at 5 km. Mid-level moisture comes and goes with the weather (`sky/altocumulus.ts`): each
13-hour spell draws its own, thinnest near midday, so most skies have none, some a patch, and
occasionally one has a whole mackerel sky, filling as much of it as the mood allows
(`altocumulusCoverage`; `altocumulusSheet` merges it into a flatter altostratus). Wind shear rolls
such a layer into billows whose crests break into rows of small cloudlets, so the cloudlets are
cells: an ordered cellular lattice in the plane, one row per crest along the shear, each cell a
soft dome of its own size. Within moist patches the moisture clumps into rafts and bands along the
crests; in their hearts the cloudlets grow large and fuse with their neighbours (a smooth minimum)
into rolls, at their fringes they shrink, scatter and go missing. The rows bend with the flow and
swell on the billows, eddies push the cells about, and finer Worley detail frays each outline and
heaps it into tufts. The layer is crossed in a few steps, each integrating exactly the share of it
below the domes' tops, and the light's way through a cloudlet is found analytically, to its rim
across the plane or out through its top or flat base, so a low sun leaves every cloudlet a lit side
and a shaded one. Lit through the atmosphere at 5 km, it keeps the sun for minutes after the heaps
below have lost it and burns rose and pink across the whole sky, then greys. Cells a sample cannot
resolve fade to their mean, so toward the horizon the field merges into an even texture instead of
sparkling. It flies twice as fast as the heaps at twice their height, the same angular drift, so
the cloud history follows it exactly.

**Shafts.** Low sunlight pours through the gaps between the heaps in beams that fan out from the
sun, and converge again opposite it at sunrise. A Beer shadow map (Hillaire 2016) looks along the
key light (the sun, or the moon at night) over the cloud layer around the observer: per texel, where
the cumulus begins toward the light, its mean extinction and its optical depth. It glides with the
drifting cloud field and turns with the light about the region around the observer, so it is redrawn
every frame at little cost and its shadows move only as the clouds and the sun do, never a texel at
a time. Its height follows the light, so a grazing sun gets all its texels, and it reaches toward
the light only as far as the heaps whose shadows fall to the ground nearby, so the heaps in and near
view cast the lanes. Each view ray is marched up to the cloud tops against it for two things: the
aerosols' forward (Mie) scattering of sunlight as if all the air were lit, reddened by the light's
path, and the share of it that is. The sky-view LUT already holds that light on average, never
broken by cloud, so what the shafts add is contrast: the beam times how far the ray's lit share
strays from its mean over wide blocks of the view (the `shaft mean` pass). Lit lanes brighten,
shaded ones darken a little (keeping their hue, never by more than 30 %), and the sky around them
keeps its glow. The contrast is amplified per mood (`shafts` in `moods.ts`, scaled against each
mood's haze), meets the sky with a film-like shoulder, and fades out as the sun climbs past 30°.

**Stars.** The stars are the real sky's: the Yale Bright Star Catalogue down to magnitude 5.5,
2,887 stars packed into 17 KB (`sky/brightstars.ts`, generated by `scripts/stars.mjs`; the
catalogue is public domain), turning with the Earth over a mid-August sky at 40° N, so Vega passes
near the zenith, Arcturus sinks in the west and the Milky Way arches overhead through Cygnus. Below
them a procedural field of fainter stars, to magnitude 8, gives the sky depth: at most one per cell
of an equi-angular cube map, their counts rising about 2.8 times per magnitude and crowding toward
the galactic plane. They are drawn by `post`, after the scene's upsampling and temporal
accumulation, at the display's own pixels, so they are pin-sharp at any pixel ratio and never
smear. The `stars` pass first sees every star once per frame (where it falls, its colour and
twinkle, what the air and the clouds let through); the catalogue is binned by cube-map cell on
the CPU, so each pixel looks only at the few stars that can reach it, and each star's light is a Gaussian integrated exactly over each pixel's
square, so its total never depends on where it falls within a pixel and nothing sparkles as the sky
turns. A faint wide halo, the lens's scattered light, shows only around the brightest, which look
larger as well as brighter. Flux follows magnitude (Pogson), colour the Planckian locus at each
star's temperature (from B − V), fading to white for faint stars as it does for the eye's rods. The
air extinguishes and reddens them through the transmittance LUT, the moon and the clouds hide them
through the scene's alpha (its view to space: thin cirrus dims them, heaps hide them), and near the
horizon they twinkle gently, with scintillation growing as air mass^1.75. Behind them the Milky Way
is a soft glow at about the airglow's brightness (`milkyway.wgsl`), brightest toward Sagittarius and
in the Cygnus star clouds, mottled and split by the Great Rift's dust; the moonlit sky washes it out.
By day none of it is looked for: even Sirius would be lost in the sky.

**Time.** As in Horizon Zero Dawn, the clouds are marched at only one pixel of every 2 × 2 cell
each frame, taking turns in Bayer order (`interleave.ts`), and every pixel keeps an average of
its own jittered marches over about ten turns (`temporal.wgsl`). The jitter is a blue-noise mask
over the cells, made by void and cluster on the CPU at startup (`bluenoise.ts`), plus an offset
per frame that strides each pixel's jitter by the golden ratio at every turn and sets the four
pixels of a cell a quarter apart: each frame's marches are spread evenly across the sky and each
pixel's evenly over time, so the average converges fast and what noise is left is fine-grained.
Everything is at infinity, so
last frame's average is found by carrying this pixel's direction back along the wind and through
last frame's camera; it is then clipped to the spread of this frame's marches around the pixel,
so churning clouds never ghost. While time is scrubbed the past is not trusted, and the pixels
between fresh marches are filled from them. Cloud motion is a pure function of simulated time,
so scrubbing the clock scrubs the clouds.

## Controls

| Input          | Effect                                                   |
| -------------- | -------------------------------------------------------- |
| scroll / drag  | wind time forward / back, slower through twilight        |
| `←` / `→`      | ease time back / forward by 15 minutes                   |
| `space`        | pause / resume time                                      |
| pointer        | a touch of parallax                                      |
| `?hour=18.4`   | start at this hour (default: a random seed)              |
| `?seed=3`      | start at one of the opening moments in `sky/seeds.ts`    |
| `?speed=0`     | time multiplier; 0 freezes the clock                     |
| `?mood=2`      | which mood the first twilight shows                      |

Moods, in order: `goldenHaze`, `violetDusk`, `emberSky`, `clear`, `softOvercast`. The sun sets at
18:52; golden hour is about 18.0–18.8, the pink and violet afterglow 18.9–19.4.

## Development

```sh
npm install
npm run dev          # http://localhost:3000
npm run typecheck    # tsc --noEmit
npm run build        # the page must stay static (○)
npm start
```

### Looking at the result

The scripts in `scripts/` drive the installed Google Chrome through Playwright with WebGPU on;
they fail fast without a WebGPU adapter and echo console errors. Serve a build first
(`npm run build && npx next start -p 3417`).

```sh
# One page, optionally a sequence from one load (writes reveal-0ms.png, …)
node scripts/screenshot.mjs --url 'http://localhost:3417/?hour=18.7&speed=0&mood=2' --out sunset.png
node scripts/screenshot.mjs --url 'http://localhost:3417/?speed=0' --out reveal.png --wait 0,1500,5000
#   --size 390x844 (default 1440x900), --dpr 2, --theme light (default dark), --headed

# A matrix of frozen skies, one PNG each: h18.8-m1-dpr2.png, …
node scripts/shots.mjs --base http://localhost:3417 --hours 7,13,18.3,18.8,19.1,23 \
  --moods 0,1 --dpr 1,2 --out .context/shots/after

# A "before" from any git ref, built in a temporary worktree and served on :3418
scripts/baseline.sh HEAD 3418

# Labelled sheets: before | after | diff ×8 per shared file name; crops; plain grids
node scripts/sheet.mjs --before .context/shots/before --after .context/shots/after --diff 8 \
  --out .context/sheets/compare.jpg
node scripts/sheet.mjs --before … --after … --crop 500,600,400,250 --scale 2 --out detail.jpg
node scripts/sheet.mjs 'noon=a.png' b.png --cols 2 --out grid.jpg

# GPU time per pass, from timestamp queries injected into the page
node scripts/frametime.mjs --url 'http://localhost:3417/?hour=18.8&speed=0'
```

`?speed=0` freezes the sun, moon and clouds, and `shots.mjs` also asks for reduced motion, which
stills the camera's breathing: only the film grain differs between two runs.

### Adding a pass

1. Write `sky/shaders/foo.wgsl` with a `@compute` entry that reads `u` (binding 0). If it
   includes `atmosphere.wgsl`, the LUT inputs are at bindings 1–4 and the output goes at binding 5
   (`outputBinding`), e.g. a `texture_storage_2d<rgba16float, write>`.
2. Add `sky/passes/foo.ts` that returns
   `createComputePass(context, { label, module, entries, workgroups })`, with entries
   `uniformsEntry(…)`, `...lutEntries(device, { transmittance })` for the LUTs it samples, and
   the output. Pipelines use `layout: 'auto'`, so list only the bindings the shader actually uses.
3. In `renderer.ts`, create the texture, pass it to the new pass and to its consumers, and put the
   pass in the graph in execution order.
