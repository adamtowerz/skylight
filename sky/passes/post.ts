/**
 * From HDR radiance to the screen: upsample, add the stars at the display's own resolution,
 * expose, vignette, tonemap, grade, paper, grain, dither, and the eyes-opening reveal from the
 * blank colour.
 */

import camera from '../shaders/camera.wgsl'
import celestial from '../shaders/celestial.wgsl'
import common from '../shaders/common.wgsl'
import cubemap from '../shaders/cubemap.wgsl'
import post from '../shaders/post.wgsl'
import seenStars from '../shaders/seenstars.wgsl'
import starfield from '../shaders/starfield.wgsl'
import starlight from '../shaders/starlight.wgsl'
import { shader } from '../shader'
import { starLayoutWgsl } from '../catalogue'
import { uniformsWgsl } from '../uniforms'
import { createFullscreenPipeline, drawFullscreen } from './fullscreen'
import { uniformsEntry, type Pass, type PassContext } from './pass'

export interface PostInputs {
  exposure: GPUBuffer
  /** The bright-star catalogue binned by cell (`sky/catalogue.ts`), and every star as seen. */
  catalogueCells: GPUBuffer
  catalogueEntries: GPUBuffer
  seen: GPUBuffer
  /** Stars in the catalogue. */
  starCount: number
  format: GPUTextureFormat
}

export async function createPostPass(
  { device, uniforms }: PassContext,
  { exposure, catalogueCells, catalogueEntries, seen, starCount, format }: PostInputs,
): Promise<Pass> {
  const sources = [uniformsWgsl, common, camera, celestial, cubemap, starLayoutWgsl(starCount), seenStars, starlight, starfield, post]
  const module = shader(device, 'post', sources)
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
          { binding: 4, resource: { buffer: catalogueCells } },
          { binding: 5, resource: { buffer: catalogueEntries } },
          { binding: 6, resource: { buffer: seen } },
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
