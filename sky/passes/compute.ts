/**
 * A compute pass that always dispatches the same work: LUTs, exposure, noise volumes.
 * Pipelines use `layout: 'auto'`, which drops bindings the shader never reads, so pass only
 * the entries the WGSL actually uses.
 */

import type { PassContext } from './pass'

/** A `Pass` that needs no render targets, so it can also run on its own (e.g. once at init). */
export interface ComputePass {
  encode(encoder: GPUCommandEncoder): void
}

export interface ComputePassOptions {
  label: string
  module: GPUShaderModule
  entries: GPUBindGroupEntry[]
  workgroups: readonly [x: number, y?: number, z?: number]
}

export async function createComputePass(
  { device }: PassContext,
  { label, module, entries, workgroups }: ComputePassOptions,
): Promise<ComputePass> {
  const pipeline = await device.createComputePipelineAsync({ label, layout: 'auto', compute: { module } })
  const bindGroup = device.createBindGroup({ label, layout: pipeline.getBindGroupLayout(0), entries })

  return {
    encode(encoder) {
      const pass = encoder.beginComputePass({ label })
      pass.setPipeline(pipeline)
      pass.setBindGroup(0, bindGroup)
      pass.dispatchWorkgroups(...workgroups)
      pass.end()
    },
  }
}
