/**
 * The HDR scene: the sky dome along every pixel's view ray, less what the clouds' shadows take
 * from the air (the light-shaft layer), behind the clouds reconstructed from the sparse cloud
 * layer and averaged over frames (temporal accumulation), all seen through the fog. Writes linear radiance, exposed and
 * tonemapped later by `post`, with each pixel's view to space for the stars `post` draws, and
 * the averaged clouds, which become the next frame's history.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import camera from '../shaders/camera.wgsl'
import celestial from '../shaders/celestial.wgsl'
import common from '../shaders/common.wgsl'
import fog from '../shaders/fog.wgsl'
import scene from '../shaders/scene.wgsl'
import sky from '../shaders/sky.wgsl'
import slab from '../shaders/slab.wgsl'
import temporal from '../shaders/temporal.wgsl'
import valueNoise from '../shaders/valuenoise.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries } from './atmosphere'
import { cloudFormat } from './cloudlayer'
import { createFullscreenPipeline, drawFullscreen } from './fullscreen'
import { milkyWayEntries } from './milkyway'
import { uniformsEntry, type Pass, type PassContext, type Targets } from './pass'

export const sceneFormat: GPUTextureFormat = 'rgba16float'

export interface SceneInputs {
  transmittance: GPUTextureView
  skyView: GPUTextureView
  milkyWay: GPUTextureView
}

export async function createScenePass({ device, uniforms }: PassContext, { milkyWay, ...luts }: SceneInputs): Promise<Pass> {
  const module = shader(device, 'scene', [uniformsWgsl, common, atmosphere, camera, celestial, valueNoise, sky, slab, fog, temporal, scene])
  const pipeline = await createFullscreenPipeline(device, 'scene', module, sceneFormat, cloudFormat)
  const fixedEntries = [...lutEntries(device, luts), ...milkyWayEntries(device, milkyWay)]
  const sampler = device.createSampler({ label: 'clouds', magFilter: 'linear', minFilter: 'linear' })

  // Two bind groups per size, one per role of the history pair. The pair, the cloud layer and the
  // shaft layers are recreated together on resize, so the history view alone tells them apart.
  const bindGroups = new WeakMap<GPUTextureView, GPUBindGroup>()
  const bindGroupFor = ({ clouds, history, shafts, shaftMean }: Targets) => {
    let bindGroup = bindGroups.get(history)
    if (!bindGroup) {
      bindGroup = device.createBindGroup({
        label: 'scene',
        layout: pipeline.getBindGroupLayout(0),
        entries: [
          uniformsEntry(uniforms),
          ...fixedEntries,
          { binding: 5, resource: clouds },
          { binding: 6, resource: history },
          { binding: 7, resource: sampler },
          { binding: 8, resource: shafts },
          { binding: 9, resource: shaftMean },
        ],
      })
      bindGroups.set(history, bindGroup)
    }
    return bindGroup
  }

  return {
    encode(encoder, targets) {
      drawFullscreen(encoder, 'scene', pipeline, bindGroupFor(targets), targets.scene, targets.accumulated)
    },
  }
}
