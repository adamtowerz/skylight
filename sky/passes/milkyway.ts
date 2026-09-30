/**
 * The Milky Way (`milkyway.wgsl`), drawn once at init into an equirectangular map of the J2000
 * equatorial sphere: it is fixed among the stars, and far too costly (a dozen octaves of noise)
 * to evaluate per pixel every frame. The scene samples it with `milkyWayEntries`.
 */

import common from '../shaders/common.wgsl'
import galactic from '../shaders/galactic.wgsl'
import milkyWay from '../shaders/milkyway.wgsl'
import valueNoise from '../shaders/valuenoise.wgsl'
import { shader } from '../shader'
import { createComputePass, type ComputePass } from './compute'
import type { PassContext } from './pass'

/** About 0.35° per texel, finer than the dust lanes. */
export const milkyWaySize = { width: 1024, height: 512 } as const
export const milkyWayFormat: GPUTextureFormat = 'rgba16float'

/** Where the scene reads the map; its sampler follows. */
const milkyWayBinding = 10

/** Runs once. It writes its only binding, 0, so it needs no uniforms. */
export function createMilkyWayPass(context: PassContext, output: GPUTextureView): Promise<ComputePass> {
  return createComputePass(context, {
    label: 'milky way',
    module: shader(context.device, 'milky way', [common, valueNoise, galactic, milkyWay]),
    entries: [{ binding: 0, resource: output }],
    workgroups: [milkyWaySize.width / 8, milkyWaySize.height / 8],
  })
}

/** Bind group entries for the map and a bilinear sampler that wraps around in right ascension. */
export function milkyWayEntries(device: GPUDevice, map: GPUTextureView): GPUBindGroupEntry[] {
  const sampler = device.createSampler({ label: 'milky way', addressModeU: 'repeat', magFilter: 'linear', minFilter: 'linear' })
  return [
    { binding: milkyWayBinding, resource: map },
    { binding: milkyWayBinding + 1, resource: sampler },
  ]
}
