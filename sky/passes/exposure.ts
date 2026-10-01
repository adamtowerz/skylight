/**
 * Exposure lives on the GPU: a compute pass meters the sky-view LUT, seen through the deck and the fog, across
 * the camera's view and writes `{ value, dome, rings }` to a storage buffer that `post` reads, so
 * auto-exposure never round-trips through the CPU.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import common from '../shaders/common.wgsl'
import decklight from '../shaders/decklight.wgsl'
import exposure from '../shaders/exposure.wgsl'
import fog from '../shaders/fog.wgsl'
import keylight from '../shaders/keylight.wgsl'
import slab from '../shaders/slab.wgsl'
import valueNoise from '../shaders/valuenoise.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries, outputBinding } from './atmosphere'
import { createComputePass } from './compute'
import { uniformsEntry, type Pass, type PassContext } from './pass'

/** Holds the WGSL `Exposure` struct (common.wgsl): an f32, a vec3f at 16, then eight vec4f rings at 32. */
export const exposureBufferSize = 32 + 8 * 16

export interface ExposureInputs {
  transmittance: GPUTextureView
  skyView: GPUTextureView
}

export function createExposurePass(context: PassContext, luts: ExposureInputs, output: GPUBuffer): Promise<Pass> {
  return createComputePass(context, {
    label: 'exposure',
    module: shader(context.device, 'exposure', [uniformsWgsl, common, atmosphere, keylight, valueNoise, slab, fog, decklight, exposure]),
    entries: [
      uniformsEntry(context.uniforms),
      ...lutEntries(context.device, luts),
      { binding: outputBinding, resource: { buffer: output } },
    ],
    workgroups: [1],
  })
}
