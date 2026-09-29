/**
 * The frame graph is an ordered list of passes. Each pass owns only its pipeline, bind groups
 * and samplers; every resource that flows between passes (buffers, LUTs, render targets) is
 * owned by the renderer and handed to the pass that needs it, so the data flow reads top to
 * bottom in `renderer.ts`.
 */

export interface PassContext {
  device: GPUDevice
  /** The shared `Uniforms` buffer, always `@group(0) @binding(0)`. */
  uniforms: GPUBuffer
}

/**
 * Per-frame render targets. Views change on resize (everything at render scale) and every frame
 * (the history pair, which swaps roles, and the output).
 */
export interface Targets {
  /** This frame's cloud layer: one jittered march per cell of the scene target. */
  clouds: GPUTextureView
  /** The cloud layer averaged over past frames, as of last frame… */
  history: GPUTextureView
  /** …and as of this one: written now, read as `history` next frame. */
  accumulated: GPUTextureView
  /** Beams of sunlight and their lit share: one texel per cell, like the cloud layer. */
  shafts: GPUTextureView
  /** The shafts' average lit share, one texel per block of `shaftBlock` pixels. */
  shaftMean: GPUTextureView
  /** HDR scene colour at render scale. */
  scene: GPUTextureView
  /** The swap chain texture for this frame. */
  output: GPUTextureView
}

export interface Pass {
  encode(encoder: GPUCommandEncoder, targets: Targets): void
}

export const uniformsEntry = (uniforms: GPUBuffer): GPUBindGroupEntry => ({
  binding: 0,
  resource: { buffer: uniforms },
})
