/**
 * The cloud layer: cumulus, altocumulus and cirrus along the view ray of one pixel in every cell of the scene
 * target (`interleave.ts`), marched with a fresh blue-noise jitter each time. The scene pass fills
 * in the other pixels from history and averages the noise away over frames.
 */

import { blueNoiseEntry } from '../bluenoise'
import altocumulus from '../shaders/altocumulus.wgsl'
import atmosphere from '../shaders/atmosphere.wgsl'
import bluenoise from '../shaders/bluenoise.wgsl'
import camera from '../shaders/camera.wgsl'
import cirrus from '../shaders/cirrus.wgsl'
import cloudlayer from '../shaders/cloudlayer.wgsl'
import clouds from '../shaders/clouds.wgsl'
import common from '../shaders/common.wgsl'
import cumulus from '../shaders/cumulus.wgsl'
import deck from '../shaders/deck.wgsl'
import decklight from '../shaders/decklight.wgsl'
import keylight from '../shaders/keylight.wgsl'
import slab from '../shaders/slab.wgsl'
import storm from '../shaders/storm.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { lutEntries } from './atmosphere'
import { createFullscreenPipeline, drawFullscreen } from './fullscreen'
import { noiseEntries } from './noise'
import { uniformsEntry, type Pass, type PassContext } from './pass'

/** rgb = radiance scattered toward the eye, a = transmittance of what lies behind. */
export const cloudFormat: GPUTextureFormat = 'rgba16float'

export interface CloudLayerInputs {
  transmittance: GPUTextureView
  skyView: GPUTextureView
  cloudNoise: GPUTextureView
  blueNoise: GPUTextureView
}

export async function createCloudLayerPass(
  { device, uniforms }: PassContext,
  { transmittance, skyView, cloudNoise, blueNoise }: CloudLayerInputs,
): Promise<Pass> {
  const module = shader(device, 'cloud layer', [
    uniformsWgsl,
    common,
    atmosphere,
    camera,
    keylight,
    clouds,
    cumulus,
    storm,
    slab,
    decklight,
    deck,
    altocumulus,
    cirrus,
    bluenoise,
    cloudlayer,
  ])
  const pipeline = await createFullscreenPipeline(device, 'cloud layer', module, cloudFormat)
  const bindGroup = device.createBindGroup({
    label: 'cloud layer',
    layout: pipeline.getBindGroupLayout(0),
    entries: [
      uniformsEntry(uniforms),
      ...lutEntries(device, { transmittance, skyView }),
      ...noiseEntries(device, cloudNoise),
      blueNoiseEntry(blueNoise),
    ],
  })

  return {
    encode(encoder, targets) {
      drawFullscreen(encoder, 'cloud layer', pipeline, bindGroup, targets.clouds)
    },
  }
}
