/**
 * The shafts' average lit share over wide blocks of the view (`shaftmean.wgsl`), which the scene
 * measures each beam against so that light shafts add contrast but no light overall.
 */

import shaftmean from '../shaders/shaftmean.wgsl'
import { shader } from '../shader'
import type { Pass, PassContext } from './pass'

/** Scene pixels across one block of the average: several lanes wide. */
export const shaftBlock = 128
/** A storage format the scene can also filter. */
export const shaftMeanFormat: GPUTextureFormat = 'rgba16float'

/**
 * Workgroups of 8 × 8 texels, dispatched for the largest average any scene target needs (64
 * blocks, 8192 px across); the shader skips texels beyond the one it has.
 */
const workgroups = 8

export async function createShaftMeanPass({ device }: PassContext): Promise<Pass> {
  const label = 'shaft mean'
  const module = shader(device, label, [shaftmean])
  const pipeline = await device.createComputePipelineAsync({ label, layout: 'auto', compute: { module } })
  const sampler = device.createSampler({ label, magFilter: 'linear', minFilter: 'linear' })

  // The layer and the average are recreated together on resize; rebuild the bind group then.
  let bound: GPUTextureView | undefined
  let bindGroup: GPUBindGroup | undefined

  return {
    encode(encoder, { shafts, shaftMean }) {
      if (shafts !== bound || !bindGroup) {
        bound = shafts
        bindGroup = device.createBindGroup({
          label,
          layout: pipeline.getBindGroupLayout(0),
          entries: [
            { binding: 1, resource: shafts },
            { binding: 2, resource: sampler },
            { binding: 3, resource: shaftMean },
          ],
        })
      }
      const pass = encoder.beginComputePass({ label })
      pass.setPipeline(pipeline)
      pass.setBindGroup(0, bindGroup)
      pass.dispatchWorkgroups(workgroups, workgroups)
      pass.end()
    },
  }
}
