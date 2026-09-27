/**
 * Sky-view LUT (Hillaire 2020): the atmosphere's radiance around the observer, relative to each
 * light's azimuth, per unit illuminance. Layer 0 is sunlit, layer 1 moonlit.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import common from '../shaders/common.wgsl'
import skyview from '../shaders/skyview.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries, outputBinding } from './atmosphere'
import { createComputePass } from './compute'
import { uniformsEntry, type Pass, type PassContext } from './pass'

/** Azimuth from the light × elevation, one layer per light. */
export const skyViewSize = { width: 192, height: 108, depthOrArrayLayers: 2 } as const

export interface SkyViewInputs {
  transmittance: GPUTextureView
  multiscattering: GPUTextureView
}

export function createSkyViewPass(context: PassContext, inputs: SkyViewInputs, output: GPUTextureView): Promise<Pass> {
  const { width, height, depthOrArrayLayers } = skyViewSize
  return createComputePass(context, {
    label: 'sky view',
    module: shader(context.device, 'sky view', [uniformsWgsl, common, atmosphere, skyview]),
    entries: [
      uniformsEntry(context.uniforms),
      ...lutEntries(context.device, inputs),
      { binding: outputBinding, resource: output },
    ],
    workgroups: [Math.ceil(width / 8), Math.ceil(height / 8), depthOrArrayLayers],
  })
}
