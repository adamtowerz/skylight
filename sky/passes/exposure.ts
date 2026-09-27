/**
 * Exposure lives on the GPU: a compute pass meters the sky-view LUT across the camera's view and
 * writes `{ value: f32 }` to a storage buffer that `post` reads, so auto-exposure never
 * round-trips through the CPU.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import common from '../shaders/common.wgsl'
import exposure from '../shaders/exposure.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries, outputBinding } from './atmosphere'
import { createComputePass } from './compute'
import { uniformsEntry, type Pass, type PassContext } from './pass'

/** Holds the WGSL `Exposure` struct (common.wgsl), padded to 16 bytes. */
export const exposureBufferSize = 16

export interface ExposureInputs {
  skyView: GPUTextureView
}

export function createExposurePass(context: PassContext, { skyView }: ExposureInputs, output: GPUBuffer): Promise<Pass> {
  return createComputePass(context, {
    label: 'exposure',
    module: shader(context.device, 'exposure', [uniformsWgsl, common, atmosphere, exposure]),
    entries: [
      uniformsEntry(context.uniforms),
      ...lutEntries(context.device, { skyView }),
      { binding: outputBinding, resource: { buffer: output } },
    ],
    workgroups: [1],
  })
}
