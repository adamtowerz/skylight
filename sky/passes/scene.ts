/**
 * The HDR scene: the sky dome along every pixel's view ray, behind the cloud layer averaged over
 * frames (temporal accumulation). Writes linear radiance, exposed and tonemapped later by `post`,
 * and the averaged clouds, which become the next frame's history.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import camera from '../shaders/camera.wgsl'
import common from '../shaders/common.wgsl'
import scene from '../shaders/scene.wgsl'
import sky from '../shaders/sky.wgsl'
import temporal from '../shaders/temporal.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries } from './atmosphere'
import { cloudFormat } from './cloudlayer'
import { createFullscreenPipeline, drawFullscreen } from './fullscreen'
import { uniformsEntry, type Pass, type PassContext, type Targets } from './pass'

export const sceneFormat: GPUTextureFormat = 'rgba16float'

export interface SceneInputs {
  transmittance: GPUTextureView
  skyView: GPUTextureView
}

export async function createScenePass({ device, uniforms }: PassContext, luts: SceneInputs): Promise<Pass> {
  const module = shader(device, 'scene', [uniformsWgsl, common, atmosphere, camera, sky, temporal, scene])
  const pipeline = await createFullscreenPipeline(device, 'scene', module, sceneFormat, cloudFormat)
  const atmosphereEntries = lutEntries(device, luts)
  const sampler = device.createSampler({ label: 'cloud history', magFilter: 'linear', minFilter: 'linear' })

  // Two bind groups per size, one per role of the history pair. The pair and the cloud layer are
  // recreated together on resize, so the history view alone tells the bind groups apart.
  const bindGroups = new WeakMap<GPUTextureView, GPUBindGroup>()
  const bindGroupFor = ({ clouds, history }: Targets) => {
    let bindGroup = bindGroups.get(history)
    if (!bindGroup) {
      bindGroup = device.createBindGroup({
        label: 'scene',
        layout: pipeline.getBindGroupLayout(0),
        entries: [
          uniformsEntry(uniforms),
          ...atmosphereEntries,
          { binding: 5, resource: clouds },
          { binding: 6, resource: history },
          { binding: 7, resource: sampler },
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
