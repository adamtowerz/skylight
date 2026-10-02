// A thunderstorm passing over, as a field across the sky. A storm is no spell that holds the whole
// sky at once but a thing that rides in on the wind: the deck it brings closes in ahead of it, its
// core arrives behind a sharp gust front, the shelf, and pours, and the sky breaks up and clears
// behind it. So everything it does is a function of where a point lies along the wind, km upwind
// of the eye: upwind is where the eye's weather is coming from, so looking that way (west-north-
// west, toward the sunset) the eye sees the storm before it arrives and the clearing before it
// goes. `weather.ts` places the edges of its windows from the timeline, as the storm passes.

// The wind the storm rides in on, from the west-north-west (unit, x = east, z = north): the
// heaps' wind, across which the deck's rolls lie (deck.wgsl).
const STORM_HEADING = vec2f(0.928, -0.371);

// How far the window `edges` (km: in from x to y, out from z to w) is open `x` km upwind.
fn stormWindow(x: f32, edges: vec4f) -> f32 {
  return smoothstep(edges.x, edges.y, x) * (1.0 - smoothstep(edges.z, edges.w, x));
}

// How far upwind of the eye a point `ground` km east and north of it lies.
fn upwind(ground: vec2f) -> f32 {
  return -dot(ground, STORM_HEADING);
}

// The storm's core over `ground`: 0 outside it, its peak at its heart.
fn stormCoreAt(ground: vec2f) -> f32 {
  return u.stormPeak * stormWindow(upwind(ground), u.stormCore);
}

// Whether a storm is anywhere about, near enough to see.
fn stormAbout() -> bool {
  return u.stormPeak > 0.0;
}

// The deck's cover over `ground`: the weather's own, and all of the sky about a storm.
fn deckCoverAt(ground: vec2f) -> f32 {
  return max(u.deckCover, smoothstep(0.0, 0.2, u.stormPeak) * stormWindow(upwind(ground), u.stormDeck));
}

// Whether a deck may be anywhere in view.
fn deckAbout() -> bool {
  return u.deckCover > 0.0 || stormAbout();
}

// Optical depth of the deck's columns where whole over `ground`: far deeper under a storm's core.
fn deckDepthOver(ground: vec2f) -> f32 {
  return mix(u.deckDepth, u.stormDepth, stormCoreAt(ground));
}

// Rain over `ground`, mm/h: the deck's light rain, and the storm's downpour under its core (as the
// square of how fierce), both surging with the gusts.
fn rainOver(ground: vec2f) -> f32 {
  let core = stormCoreAt(ground) / max(u.stormPeak, 1e-3);
  return (u.rainRate + u.stormRain * core * core) * u.rainGust;
}
