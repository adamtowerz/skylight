/**
 * Light shafts: the beams of sunlight through the gaps between the heaps, scattered toward the eye
 * by the haze, marched against the cloud shadow map (`shafts.wgsl`) at one pixel per cell of the
 * scene target. The scene adds their contrast (lit lanes brighter, shaded ones darker) to the sky
 * between the clouds.
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import camera from '../shaders/camera.wgsl'
import cloudshadow from '../shaders/cloudshadow.wgsl'
import common from '../shaders/common.wgsl'
import keylight from '../shaders/keylight.wgsl'
import shaftlayer from '../shaders/shaftlayer.wgsl'
import shafts from '../shaders/shafts.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries } from './atmosphere'
import { createFullscreenPipeline, drawFullscreen } from './fullscreen'
import { uniformsEntry, type Pass, type PassContext } from './pass'
import { cloudShadowEntry } from './shadowmap'

/** rgb = beam radiance were all the air lit, a = the share of it that is. */
export const shaftFormat: GPUTextureFormat = 'rgba16float'

export interface ShaftInputs {
  transmittance: GPUTextureView
  cloudShadow: GPUTextureView
}

export async function createShaftPass({ device, uniforms }: PassContext, { cloudShadow, ...luts }: ShaftInputs): Promise<Pass> {
  const module = shader(device, 'light shafts', [
    uniformsWgsl,
    common,
    atmosphere,
    camera,
    keylight,
    cloudshadow,
    shafts,
    shaftlayer,
  ])
  const pipeline = await createFullscreenPipeline(device, 'light shafts', module, shaftFormat)
  const bindGroup = device.createBindGroup({
    label: 'light shafts',
    layout: pipeline.getBindGroupLayout(0),
    entries: [uniformsEntry(uniforms), ...lutEntries(device, luts), cloudShadowEntry(cloudShadow)],
  })

  return {
    encode(encoder, targets) {
      drawFullscreen(encoder, 'light shafts', pipeline, bindGroup, targets.shafts)
    },
  }
}
