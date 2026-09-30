/**
 * Every star as it is seen this frame (`stars.wgsl`), the catalogue's and the faint field's: one
 * invocation per star works out where it falls on the display and how much of its light gets
 * through the air and the clouds, so that `post` only spreads each star's light over its pixels.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import camera from '../shaders/camera.wgsl'
import celestial from '../shaders/celestial.wgsl'
import common from '../shaders/common.wgsl'
import cubemap from '../shaders/cubemap.wgsl'
import faintStars from '../shaders/faintstars.wgsl'
import galactic from '../shaders/galactic.wgsl'
import seenStars from '../shaders/seenstars.wgsl'
import seeStar from '../shaders/seestar.wgsl'
import starlight from '../shaders/starlight.wgsl'
import stars from '../shaders/stars.wgsl'
import { seenStarSlots, starLayoutWgsl } from '../catalogue'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries } from './atmosphere'
import { uniformsEntry, type Pass, type PassContext } from './pass'

const workgroupSize = 64

export interface StarsInputs {
  transmittance: GPUTextureView
  /** `Star`s, 32 bytes each (`sky/catalogue.ts`). */
  catalogue: GPUBuffer
  /** One `SeenStar` per slot (`seenstars.wgsl`), written here and read by `post`. */
  seen: GPUBuffer
  /** Stars in the catalogue. */
  count: number
}

export async function createStarsPass(
  { device, uniforms }: PassContext,
  { transmittance, catalogue, seen, count }: StarsInputs,
): Promise<Pass> {
  const module = shader(device, 'stars', [uniformsWgsl, common, atmosphere, camera, celestial, galactic, cubemap, starLayoutWgsl(count), seenStars, starlight, seeStar, faintStars, stars])
  const pipeline = await device.createComputePipelineAsync({ label: 'stars', layout: 'auto', compute: { module } })
  const fixedEntries = [
    uniformsEntry(uniforms),
    ...lutEntries(device, { transmittance }),
    { binding: 7, resource: device.createSampler({ label: 'stars', magFilter: 'linear', minFilter: 'linear' }) },
    { binding: 8, resource: { buffer: catalogue } },
    { binding: 9, resource: { buffer: seen } },
  ]

  // The scene target is recreated on resize; rebuild the bind group only when it changes.
  let boundScene: GPUTextureView | undefined
  let bindGroup: GPUBindGroup | undefined
  const bindGroupFor = (scene: GPUTextureView) => {
    if (scene !== boundScene || !bindGroup) {
      boundScene = scene
      bindGroup = device.createBindGroup({
        label: 'stars',
        layout: pipeline.getBindGroupLayout(0),
        entries: [...fixedEntries, { binding: 6, resource: scene }],
      })
    }
    return bindGroup
  }

  return {
    encode(encoder, targets) {
      const pass = encoder.beginComputePass({ label: 'stars' })
      pass.setPipeline(pipeline)
      pass.setBindGroup(0, bindGroupFor(targets.scene))
      pass.dispatchWorkgroups(Math.ceil(seenStarSlots(count) / workgroupSize))
      pass.end()
    },
  }
}
