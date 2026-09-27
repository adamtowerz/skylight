/**
 * The atmosphere LUTs (Hillaire 2020) as the shaders see them. `atmosphere.wgsl` declares them
 * at fixed bindings, 1–3 plus a linear sampler at 4; compute passes write their output at 5.
 * Pipelines use `layout: 'auto'`, so a pass binds only the LUTs its entry point reads.
 */

export const lutFormat: GPUTextureFormat = 'rgba16float'

/** Where a compute pass that includes `atmosphere.wgsl` writes its result. */
export const outputBinding = 5

export interface AtmosphereLuts {
  transmittance?: GPUTextureView
  multiscattering?: GPUTextureView
  /** A 2D array: one layer per light (0 = sun, 1 = moon). */
  skyView?: GPUTextureView
}

const bindings = { transmittance: 1, multiscattering: 2, skyView: 3 } as const
const samplerBinding = 4

/** Bind group entries for the given LUTs and the sampler that reads them (clamped, bilinear). */
export function lutEntries(device: GPUDevice, luts: AtmosphereLuts): GPUBindGroupEntry[] {
  const sampler = device.createSampler({ label: 'atmosphere', magFilter: 'linear', minFilter: 'linear' })
  const views = (Object.keys(bindings) as (keyof AtmosphereLuts)[]).flatMap((name) => {
    const view = luts[name]
    return view ? [{ binding: bindings[name], resource: view }] : []
  })
  return [...views, { binding: samplerBinding, resource: sampler }]
}
