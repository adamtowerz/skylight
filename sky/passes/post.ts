/**
 * From HDR radiance to the screen: upsample, expose, vignette, tonemap, grade, paper, grain,
 * dither, and the eyes-opening reveal from the blank colour.
 */

import common from '../shaders/common.wgsl'
import post from '../shaders/post.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { createFullscreenPipeline, drawFullscreen } from './fullscreen'
import { uniformsEntry, type Pass, type PassContext } from './pass'

export interface PostInputs {
  exposure: GPUBuffer
  format: GPUTextureFormat
}

export async function createPostPass({ device, uniforms }: PassContext, { exposure, format }: PostInputs): Promise<Pass> {
  const module = shader(device, 'post', [uniformsWgsl, common, post])
  const pipeline = await createFullscreenPipeline(device, 'post', module, format)
  const sampler = device.createSampler({ label: 'post', magFilter: 'linear', minFilter: 'linear' })

  // The scene target is recreated on resize; rebuild the bind group only when it changes.
  let boundScene: GPUTextureView | undefined
  let bindGroup: GPUBindGroup | undefined
  const bindGroupFor = (scene: GPUTextureView) => {
    if (scene !== boundScene || !bindGroup) {
      boundScene = scene
      bindGroup = device.createBindGroup({
        label: 'post',
        layout: pipeline.getBindGroupLayout(0),
        entries: [
          uniformsEntry(uniforms),
          { binding: 1, resource: { buffer: exposure } },
          { binding: 2, resource: scene },
          { binding: 3, resource: sampler },
        ],
      })
    }
    return bindGroup
  }

  return {
    encode(encoder, targets) {
      drawFullscreen(encoder, 'post', pipeline, bindGroupFor(targets.scene), targets.output)
    },
  }
}
