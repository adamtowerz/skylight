/**
 * The cloud shadow map: the cumulus as the key light sees it, as a Beer shadow map (Hillaire
 * 2016) over the cloud layer and the air below it (`cloudshadow.wgsl`). Low resolution and redrawn
 * every frame, which costs little: under a grazing sun its texels crowd onto the thin band the
 * layer makes along the light, and it follows the drifting clouds without history. The light
 * shafts read it (`shafts.wgsl`).
 */

import atmosphere from '../shaders/atmosphere.wgsl'
import cirrus from '../shaders/cirrus.wgsl'
import cloudshadow from '../shaders/cloudshadow.wgsl'
import clouds from '../shaders/clouds.wgsl'
import common from '../shaders/common.wgsl'
import cumulus from '../shaders/cumulus.wgsl'
import keylight from '../shaders/keylight.wgsl'
import shadowmap from '../shaders/shadowmap.wgsl'
import { shader } from '../shader'
import { uniformsWgsl } from '../uniforms'
import { createComputePass } from './compute'
import { noiseEntries } from './noise'
import { uniformsEntry, type Pass, type PassContext } from './pass'

/** Across the light × across it in its vertical plane: texels ≈ 190 m across. */
export const shadowMapSize = { width: 256, height: 256 } as const
/** Premultiplied (front, mean extinction, optical depth), as `cloudshadow.wgsl` reads it. */
export const shadowMapFormat: GPUTextureFormat = 'rgba16float'

/** Where `shadowmap.wgsl` writes the map; readers sample it at `cloudShadowBinding`. */
const outputBinding = 7
const cloudShadowBinding = 8

/** The bind group entry for passes that read the map (with the atmosphere's sampler). */
export const cloudShadowEntry = (map: GPUTextureView): GPUBindGroupEntry => ({ binding: cloudShadowBinding, resource: map })

export interface ShadowMapInputs {
  cloudNoise: GPUTextureView
}

export function createShadowMapPass(context: PassContext, { cloudNoise }: ShadowMapInputs, output: GPUTextureView): Promise<Pass> {
  const { width, height } = shadowMapSize
  return createComputePass(context, {
    label: 'cloud shadow',
    module: shader(context.device, 'cloud shadow', [
      uniformsWgsl,
      common,
      atmosphere,
      keylight,
      cloudshadow,
      clouds,
      cumulus,
      cirrus,
      shadowmap,
    ]),
    entries: [
      uniformsEntry(context.uniforms),
      ...noiseEntries(context.device, cloudNoise),
      { binding: outputBinding, resource: output },
    ],
    workgroups: [Math.ceil(width / 8), Math.ceil(height / 8)],
  })
}
