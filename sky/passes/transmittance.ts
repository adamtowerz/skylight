/**
 * Transmittance LUT (Hillaire 2020, Bruneton's mapping): the fraction of light surviving from any
 * altitude and direction to space. Rebuilt every frame, because moods change the air.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import common from '../shaders/common.wgsl'
import transmittance from '../shaders/transmittance.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { outputBinding } from './atmosphere'
import { createComputePass } from './compute'
import { uniformsEntry, type Pass, type PassContext } from './pass'

/** μ (distance to the top of the atmosphere) × r. */
export const transmittanceSize = { width: 256, height: 64 } as const

export function createTransmittancePass(context: PassContext, output: GPUTextureView): Promise<Pass> {
  return createComputePass(context, {
    label: 'transmittance',
    module: shader(context.device, 'transmittance', [uniformsWgsl, common, atmosphere, transmittance]),
    entries: [uniformsEntry(context.uniforms), { binding: outputBinding, resource: output }],
    workgroups: [transmittanceSize.width / 8, transmittanceSize.height / 8],
  })
}
