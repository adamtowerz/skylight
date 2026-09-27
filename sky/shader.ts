/**
 * WGSL has no imports, so modules are composed by concatenation in dependency order, e.g.
 * `shader(device, 'scene', [uniformsWgsl, common, atmosphere, camera, sky, temporal, scene])`.
 */
export function shader(device: GPUDevice, label: string, sources: readonly string[]): GPUShaderModule {
  return device.createShaderModule({ label, code: sources.join('\n') })
}
