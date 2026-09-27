/**
 * Full-screen fragment passes: one oversized triangle (`fullscreen` in common.wgsl) covering
 * the target, with all the work in the fragment shader. A pass may write several targets at
 * once, one per `@location`, given in the same order as their formats.
 */

export function createFullscreenPipeline(
  device: GPUDevice,
  label: string,
  module: GPUShaderModule,
  ...formats: GPUTextureFormat[]
): Promise<GPURenderPipeline> {
  return device.createRenderPipelineAsync({
    label,
    layout: 'auto',
    vertex: { module, entryPoint: 'fullscreen' },
    fragment: { module, targets: formats.map((format) => ({ format })) },
    primitive: { topology: 'triangle-list' },
  })
}

export function drawFullscreen(
  encoder: GPUCommandEncoder,
  label: string,
  pipeline: GPURenderPipeline,
  bindGroup: GPUBindGroup,
  ...views: GPUTextureView[]
) {
  const pass = encoder.beginRenderPass({
    label,
    colorAttachments: views.map((view) => ({ view, loadOp: 'clear', storeOp: 'store', clearValue: [0, 0, 0, 1] })),
  })
  pass.setPipeline(pipeline)
  pass.setBindGroup(0, bindGroup)
  pass.draw(3)
  pass.end()
}
