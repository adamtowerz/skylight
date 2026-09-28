---
name: render-review
description: Visual iteration loop for Skylight's WebGPU sky. Use whenever changing, tuning, verifying or comparing how the sky renders or looks (atmosphere, clouds, moods, exposure, post/grade, reveal, TAA, DPR, performance), before claiming a visual change works, or when asked for screenshots, contact sheets or before/after comparisons.
---

# Render review

Nothing about the look is done until you have seen it. Build, serve on a private port, render a
matrix of frozen skies, **open every image yourself**, and compare against a baseline build in
labelled sheets. All tools are in `scripts/` (Playwright + installed Chrome, no Python).

## 1. Build and serve (port 3417 is yours)

```sh
lsof -nP -iTCP:3417 -sTCP:LISTEN            # must be empty, or the old build answers
npx next build && npx next start -p 3417     # run the start in the background
```

After every code change: stop the server, rebuild, restart. `next start` runs a `next-server`
child that outlives its `npx` parent, so stop it by port and check the port is free:
`lsof -nP -tiTCP:3417 -sTCP:LISTEN | xargs kill`. Only kill ports you started; others
(e.g. 3000) belong to other sessions. A stale server is the most common way to "verify" code
that is not running.

## 2. Baseline ("before")

```sh
scripts/baseline.sh HEAD 3418      # background it; worktree in /tmp/skylight-HEAD, serves :3418
# … compare …
lsof -nP -tiTCP:3418 -sTCP:LISTEN | xargs kill && git worktree remove --force /tmp/skylight-HEAD
```

Any ref works (`HEAD~2`, a sha). HEAD is the usual baseline for uncommitted work.

## 3. Render the matrix

```sh
node scripts/shots.mjs --base http://localhost:3418 --out .context/shots/before
node scripts/shots.mjs --base http://localhost:3417 --out .context/shots/after
#   [--hours 7,13,18.3,18.8,19.1,23] [--moods 0,1,2] [--dpr 1,2] [--theme dark,light]
#   [--size 1440x900] [--wait 6000] [--params 'speed=1'] [--motion]
```

Files: `h<hour>[-m<mood>][-dpr<n>][-<theme>].png`, so identical arguments pair up. Every shot
has `speed=0` and reduced motion (no camera breathing), so two builds line up to the pixel. Shots
run one page at a time on purpose; parallel pages starve each other's GPU and get caught
mid-reveal. About 6.5 s per shot.

Hours worth looking at (the camera looks up toward the sunset, WNW; the sky turns overhead):

| `hour`    | shows                                                                          |
| --------- | ------------------------------------------------------------------------------ |
| 5.0       | dawn: pink cirrus over dark cumulus (sunrise is at 5:08, behind the viewer)    |
| 5.3–5.8   | sunrise light: peach heaps turning cream on a pale blue                        |
| 7         | morning: low sun behind the viewer, warm-lit heaps on blue                     |
| 13        | noon, sun in frame top-left: silver linings, blue shaded sides                 |
| 18.0–18.8 | golden hour: gold heaps, haze glow at the bottom (18.3 standard)               |
| 18.8      | the hero frame: sunset, rose clouds on violet                                  |
| 18.87     | sunset at the ground; undersides keep the light                                |
| 18.9–19.4 | pink/violet afterglow; cirrus glows last (19.1 standard)                       |
| 19.3–19.8 | blue hour, ozone violet; −6° at 19.43, −12° at 20.03                           |
| 21–4      | night: airglow floor, stars, moon-lit silver rims (23 standard)                |

Moods (`?mood=n`, `sky/moods.ts`): 0 `goldenHaze`, 1 `violetDusk`, 2 `emberSky`, 3 `clear`,
4 `softOvercast`. A mood holds through a twilight (within ~3 h of 06:00 / 18:00) and crossfades
around noon and midnight, so at 13 or 23 `?mood=n` is partly blended with its neighbour. For a
twilight change, sweep `--hours 18.6,18.8,18.9,19.0,19.2,19.4,19.6 --moods 0,1,2,3,4`.

## 4. Look, then compare

Open every PNG with Read. Then build sheets (use `.jpg` output: multi-MB PNG sheets get
downsampled into false banding by the image viewer):

```sh
# before | after | amplified diff, one row per shared file name
node scripts/sheet.mjs --before .context/shots/before --after .context/shots/after \
  --diff 8 --width 480 --title 'what changed' --out .context/sheets/compare.jpg
# 1:1 (or magnified, nearest-neighbour) detail: crop x,y,w,h in source pixels
node scripts/sheet.mjs --before … --after … --match 'h18.8' --crop 500,600,400,250 --scale 2 \
  --diff 16 --out .context/sheets/detail.jpg
# any labelled images as a grid
node scripts/sheet.mjs 'noon=.context/shots/after/h13.png' .context/shots/after/h23.png --cols 2 \
  --out .context/sheets/grid.jpg
```

The diff statistics are printed too. Noise floor between two runs of one build is grain only:
even speckle, mean ≈ 0.1 or ≈ 3–4 (depends on which grain frame was caught), max ≲ 30. Real
changes show structure (cloud edges, gradients). Unintended structure in rows you did not mean to
touch is a regression. Keep full sheets to ≲ 6 rows × 3 at `--width 480`; for detail use crops.
DPR 2 shots are 2880 px wide: judge them through 1:1 crops, not by viewing the whole file.

These sheets are what the user finds most useful for reviewing work: show them (paths) in your
report.

## 5. Checks beyond the still matrix

- **Both DPRs and themes**: `--dpr 1,2 --theme dark,light` on at least 18.8 and 23. Grain and
  dither sit on device pixels; the scene renders at ≤ 1.1 MP and is upsampled, so DPR 2 is where
  softness and upsampling artefacts show.
- **Reveal**: `node scripts/screenshot.mjs --url 'http://localhost:3417/?hour=18.8&speed=0' --out .context/reveal.png --wait 0,1500,5000 --theme light`
  (and dark). The 0 ms frame must be exactly `#fff` (light) / `#000` (dark), no grain; 1500 ms
  a soft radial opening; 5000 ms the settled sky.
- **Motion**: `--params 'speed=20' --motion --wait 2000,6000,10000` (or `speed=1`): clouds must
  drift without smearing, ghosting or shimmer; exposure must not pump. Scrubbing (scroll, arrow keys)
  resets the TAA history by design.
- **Frame time**: `node scripts/frametime.mjs --url 'http://localhost:3417/?hour=18.8&speed=0&mood=1'`
  prints median/p90 GPU ms per pass (timestamp queries injected from outside the engine). Budget
  ≲ 8 ms at 1440×900 on the M1 Pro (about 6 ms today: cloud layer ≈ 4.2, scene 0.6, post 0.4,
  exposure 0.4). GPU clocks vary: measure before and after back to back, and check a cloudy
  mood too (`mood=4`, `softOvercast`, has the most cover to march).

## Failure modes checklist

- Stale server: the change "did nothing" (or the diff is pure grain) → rebuild and restart, check
  the port.
- Captured too early: TAA (≈ 10 frames) and exposure (adapts at 1.5/s) need ~6 s; a half-open
  radial mask means the page was starved or the wait too short.
- NaN / Inf: black or oddly coloured pixels, black blocks that spread through the TAA history, a
  whole black frame (exposure buffer poisoned). Check `max()`/`sqrt`/`pow` of negatives and divisions.
- Banding in gradients (twilight sky, near the sun, dark night sky): check at 1:1; the dither
  should hide it. Don't trust banding seen only in a large downsampled sheet.
- Shimmer / popping: cloud edges or cirrus fibres flicker between frames; compare two waits of a
  `--motion` run, or crop the same area from `--wait 6000,6500`.
- Exposure pumping: brightness breathing as clouds drift; watch a `speed=20` sequence.
- Ghosting / smearing behind moving clouds; stars or the sun smeared (they must never be
  accumulated).
- Console errors are echoed by the scripts (`[error] …`): WGSL compile errors, validation
  errors, a missing WebGPU adapter (retry `--headed`). A still CSS gradient instead of the sky
  means the engine fell back.
- Mood leakage: a change meant for one mood or hour altering the others (check every diff row).
