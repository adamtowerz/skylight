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
| `exposure`        | storage buffer `{ value, dome, rings }` | meters the sky-view LUT through the deck and fog over the view; compressed key; adapts; the dome's mean, and in rings, for the rain |
| `cloud shadow`    | `rgba16float` 256×256           | Beer shadow map of the cumulus along the key light (Hillaire 2016)      |
| `light shafts`    | `rgba16float`, ¼ of the scene   | beams of sunlight through the gaps between the heaps, and lit share     |
| `shaft mean`      | `rgba16float`, 1 per 128 px     | the lit share averaged over wide blocks, so shafts add only contrast    |
| `cloud layer`     | `rgba16float`, ¼ of the scene   | one ray per 2 × 2 cell → deck, cumulus, altocumulus, cirrus (radiance, T) |
| `scene`           | `rgba16float` scene + history   | clouds rebuilt + averaged over frames, over the sky, sun, moon, Milky Way; fog |
| `stars`           | storage buffer, 1 per star      | each star's place, colour, twinkle and light through the air and clouds |
| `post`            | swap chain                      | upsample, stars, rain, exposure, vignette, AgX, grade, paper, grain, dither, reveal |

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
its sample can, so none alias into sparkle as the heaps drift. Density rises from a soft,
translucent rim a few hundred metres deep into a core as dense as real cumulus, so heaps keep soft volume yet darken their
own bases and crevices. A heap turns opaque within far less than a step of
the view ray, so between two samples the march takes the field to run linearly and integrates the
cloud's sharp threshold along the step exactly, and lights each step where the light it sends to
the eye comes from on average (near the front of a thick step): heap edges move smoothly across
the steps instead of falling into contour lines, at no extra samples. Sunlight reaches every sample through the transmittance LUT, so after the sun sets at
the ground the clouds keep catching it, gold, then rose, then the altocumulus and cirrus alone glow pink. Direct
light uses a short light march, a dual-lobe phase function (the silver lining) and
multiple-scattering octaves after Wrenninge et al. 2013. Light scattered many times comes in by
whichever way brings more: along the light, or diffused down from the sunlit crown through the
column above the sample (a second, three-step march), carried by two-stream diffusion (Bohren 1987)
and weighted by how much of the light the crown catches, which under a grazing sun is little.
The rest of a grazing sun falls on the flanks facing it and diffuses in sideways from them, leaking
out through the base and the top as it goes, so it dies away as a slab's fundamental diffusion
mode, over about the heap's own depth. So at golden hour the flanks and turrets facing the sun
blaze while the bases of flat heaps sink into their own shade, and those of tall banks, which the
light crosses far before it leaks away, glow a dim gold deep in: the heaps have form instead of
one even glow, and their cores stay warm instead of turning grey. Ambient light is the sky-view LUT, with shaded sides seeing
only the half of the sky turned from the sun (blue shadows at noon, violet at dusk), and grass
bounce from below, both dimmed by the cloud they diffuse through, the skylight from above by the
column the second march measures. At night the moon lights them, and they stand dark against the
airglow with silver rims.

**Mackerel sky.** Now and then a layer of altocumulus a few hundred metres deep lies between
them at 5 km. Mid-level moisture comes and goes with the weather (`sky/weather.ts`): each
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

**Weather.** Moods are each twilight's flavour; weather comes and goes on top of them, as a pure
function of simulated time (`sky/weather.ts`), so a given `?hour=` always shows the same sky. Each
kind of weather arrives in spells: every spell draws a random amount (a hash of its index, with a
salt per kind, so the kinds are independent), eased into the next, and the kind shows once the
draw passes a threshold, so most spells bring none, some a little and a few the whole thing. The
hour of day then shapes it after the physics that makes it. The mackerel sky is one kind, thinnest
at midday. *Radiation fog* forms on still, humid nights as the ground cools, thickens from 23:00 to
04:00, is thickest around sunrise and burns off between 06:30 and 09:30: misty sunrises, about one
morning in three, most of them a mist the heaps glow through and only rarely a thick bank. *Haze* builds through warm afternoons, lasts through the golden hour and settles out in
the night; it multiplies the mood's aerosols (and lifts them a little higher), so the Hillaire
atmosphere does the rest: a whiter sky, a softer sun, redder and dimmer heaps, stronger light
shafts. The salts are chosen so the opening seeds keep their skies.

Fog is a layer of droplets on the ground with the eye inside it (`fog.wgsl`): 60–200 m of it
above the eye, visibility down to about 400 m, so even the thickest still shows the sun's disc and
the brightest heaps: seeing the sky is the point. It is thin and nearly uniform, and droplets far larger than
the light's wavelengths scatter every colour alike, so it needs no march: it is a plane-parallel
slab of grey, conservative scatterers, solved in closed form per pixel. Everything beyond it (sky,
shafts, clouds, sun, moon, and through the scene's alpha the stars) is dimmed by exp(−τ/μ), so thin
fog still shows blue straight up and hides it at a slant. The light it takes away comes out below
as a glow: how much of the sunlight on its top gets through is the two-stream (Eddington) solution
for a conservative slab, and where it seems to come from broadens with every scattering (the
droplets' forward phase, g ≈ 0.85, raised to the number of scatterings), so a thin mist glows
around the sun and a thick bank is evenly luminous. Half of what a droplet takes out of a beam
it only diffracts, a few degrees forward, and that light is the sun's soft white disc and its
aureole. The whole sky dome lights the fog, weighted as the irradiance it sends onto its top, and
the grass bounces part of what gets through back up, so the fog mixes every colour of the sky into
one milky light; moonlight does what sunlight does, so at night the moon hangs in a pale halo while
the stars fade. Fog lies in banks a few kilometres across, so a low sun slants in a little through
their tops and sides: at sunrise the fog glows peach, at sunset rose. Its top is ragged, its
thickness breathing with slow noise drawn out along the breeze at the ground into soft wisps, so
the veil thins into patches where the blue and the heaps show through; and the lower in the view,
the more fog the eye looks through. Exposure meters the fogged sky, and like a photographer
exposing for fog or snow it opens up by up to 0.8 stop as the fog veils the view, so fog reads as
luminous rather than grey. When there is no fog none of this is computed.

About one day in six a front brings a *deck*, a low grey layer of stratus and nimbostratus
(`deck.wgsl`), on spells of its own, whatever the hour: first a broken stratocumulus at 1.2 km
with blue (or the sunset) between its cells, then, as it lowers to 600 m and thickens, the
unbroken grey dome of a rainy day. It is far too thick and even to march, so like the fog it is a
slab solved in closed form (`slab.wgsl`, shared with the fog), found where each view ray meets
its base: the key light and the whole dome light its top, and what the eye sees is what diffuses
through (`decklight.wgsl`), so its underside is a luminous soft grey, brighter where it is thinner
and toward the sun, and limb-darkened like light escaping a star (the CIE overcast sky is about
three times brighter overhead than at the horizon). A broken deck lies in rows along rolls across
the wind, never evenly: eddies push the rolls together and apart and they fade and strengthen
along their length, so rows merge, split and break into cells, drawn out along them, lumpy, and
frayed into wisps where they thin out at their edges. An edge's column grows as the cube of the
way in, so it is a veil a good way in, not a contour. Each column is lit as a slab, but light also
diffuses sideways through the deck over about its depth (radiative smoothing), so a thin edge is
a veil of the diffuse light of the cell it frays from rather than a glowing outline; only the
light it diffracts, close around the sun or moon, is its own silver lining, and since the edge
thickens gradually that lining is a soft band. The top takes in a low sun only as the sine of its elevation, so
at sunset a whole deck is lit by the sky above it, a dim grey of the dusk's own colour. Its base
is never flat: the rolls, cells and lumps deepen and thin the column, darker where it is deeper
and sags lower, even in a whole deck, and under a whole deck ragged scud hurries past beneath,
lower and so faster across the sky. At
sunset the deck can catch fire from below: a sun just under the horizon shines up along a path
that dips beneath the base and climbs back to its height tens of kilometres off, so where the deck
breaks there the low red light floods in and lights the underside of the rolls that face it. The
gap is the share of the many kilometres over which the path climbs through the base that is open,
and on the way in the light skims beneath the base's lumps: those that hang lower toward the light
shade the base behind them, so the underside is lit on the flanks of its lumps and rolls that face
the light and dims in their lee, while thin edges, which it shines through, are a veil of their
cell's glow. A deck also shades the ground that feeds the heaps' thermals and caps them under its
inversion: as it closes in the heaps stop towering, stay lower and spread out, their domes thinning
gradually to their edges, and grow fewer and thinner, so a broken deck still has heaps in its gaps
and only a nearly whole one has none. Its cells stand about as tall above the base as they are
deep, and beside them the heaps' lower flanks and bases lie among their tops: under a low sun the
cells between a heap and the light shade it in soft patches, lit through the gaps, each shadow's
penumbra widening with its way from the cell (light diffused through and around the cell, far
wider than the sun's disc), while the light it scatters many times still comes down from its crown where that stands in the sun. The
deck hides whatever lies above it through the scene's alpha (heaps, mackerel sky, cirrus, moon and
stars), its optical depth joins the cumulus in the shadow map, so a whole deck shades the light
shafts away, and the exposure meters the sky through it and opens up as it veils the view, so a
grey day reads soft rather than muddy. It comes in on clean air behind a front, so the far haze
that reddens the sunlight goes as it closes in, and it allows no radiation fog.

Rain falls only from a thick deck, in showers a few hours long (`precipitation`, 1 being light
rain, 2 mm/h). The rain between the deck and the eye veils the sky a little with the light under
the deck, and washes some aerosol out of the air. The nearest few metres of it are drawn drop by
drop by `post` at the display's own pixels (`rain.wgsl`), after the temporal accumulation, so
the streaks are crisp and never smeared. Lying on our back, the rain comes straight down at us, so
every drop's path radiates from one vanishing point near the zenith, tilted upwind by the breeze,
and lengthens toward the edges of the view. The drops live on nested cylinders about the fall line
(Tatarchuk 2006's rain layers, turned upward), each a lattice in azimuth and cot θ scrolling at the
drops' fall speed, one hashed drop per cell at most, so a pixel looks at only a few cells. Each drop
is a streak where it fell during the eye's exposure (about as long as the eye holds an image, so
one frame's streak meets the next and the fall reads as motion), round-ended as a sphere sweeps,
box-filtered over each pixel so none crawls, and blurred by the eye's focus on the sky, so the
nearest drift past large and soft. Drops near the vanishing point, falling almost straight at us,
would be still specks and far ones dust, so they fade out, leaving a calm opening the rain streams
out of. A drop's light is that of a glass bead (`raindrop.wgsl`, after Garg & Nayar and Rousseau et
al. 2006): it is a fisheye that shows the world around it inverted, so its middle shows the sky
straight behind it and its rim the sky some 80° beyond, plus a Fresnel glint of what lies behind
us. It refracts the frame itself where that is in view and otherwise the dome in rings (metered by
the exposure pass), with the wet grass below the horizon: bright at heart, dark at the rim, warm
where it catches a glow. Under an even grey deck that differs from the sky behind it by only a few
per cent, which a still all but loses and the eye, sensitive to motion, does not, so the contrast
is amplified in stops, bounded, keeping its sign and colour. Their number and size follow Marshall
& Palmer from the rain rate, so heavier rain is the same drops, more, larger and faster. Far rain is not drawn drop by drop: its drops are finer than a
pixel and their share of each falls as fast as their number grows, so it sums to the deck's veil.

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
| `?fog=0.6`     | hold a kind of weather (`fog`, `haze`, `altocumulus`, `deck`, `precipitation`) at a value 0–1 |

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
