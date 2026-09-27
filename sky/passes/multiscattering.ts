/**
 * Multiscattering LUT (Hillaire 2020): ψ_ms, every scattering order past the first, by altitude
 * and light elevation. One 64-thread workgroup per texel, one sphere direction per thread.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import common from '../shaders/common.wgsl'
import multiscattering from '../shaders/multiscattering.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries, outputBinding } from './atmosphere'
import { createComputePass } from './compute'
import { uniformsEntry, type Pass, type PassContext } from './pass'

/** Light zenith cosine × altitude. */
export const multiscatteringSize = { width: 32, height: 32 } as const

export interface MultiscatteringInputs {
  transmittance: GPUTextureView
}

export function createMultiscatteringPass(
  context: PassContext,
  { transmittance }: MultiscatteringInputs,
  output: GPUTextureView,
): Promise<Pass> {
  return createComputePass(context, {
    label: 'multiscattering',
    module: shader(context.device, 'multiscattering', [uniformsWgsl, common, atmosphere, multiscattering]),
    entries: [
      uniformsEntry(context.uniforms),
      ...lutEntries(context.device, { transmittance }),
      { binding: outputBinding, resource: output },
    ],
    workgroups: [multiscatteringSize.width, multiscatteringSize.height],
  })
}
