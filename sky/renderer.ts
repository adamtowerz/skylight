/**
 * Owns every GPU resource that flows between passes and encodes the frame graph:
 *
 *   noise (compute, once at init)                           cloud noise volume
 *   milky way (compute, once at init)                       its map over the celestial sphere
 *   blue noise (CPU, once at init)                          jitter mask
 *   star catalogue (CPU, once at init)                      bright stars, binned by cell
 *   uniforms → transmittance → multiscattering → sky view   (atmosphere LUTs, compute)
 *            → exposure (compute)
 *            → cloud shadow (compute, the cumulus seen from the key light)
 *            → light shafts (one pixel per cell) → shaft mean (their average lit share)
 *            → cloud layer (one pixel per cell) → scene (HDR + cloud history, render scale)
 *                                               → stars (every star as seen this frame, compute)
 *                                               → post (+ stars, swap chain) → edges (readback, optional)
 *
 * Passes are created in parallel with async pipelines, then run in order every frame. The LUTs
 * are rebuilt every frame too: moods change the air, and together they cost well under a
 * millisecond. The cloud history is a ping-pong pair: each frame the scene pass reads one and
 * writes the other.
 */

import { blueNoise, blueNoiseFormat, blueNoiseSize } from './bluenoise'
import { seenStarSize, seenStarSlots, starCatalogue } from './catalogue'
import { createEdgeSampler, type EdgeColors } from './edges'
import type { Gpu } from './gpu'
import { cloudCell } from './interleave'
import type { Vec2 } from './math'
import { lutFormat } from './passes/atmosphere'
import type { ComputePass } from './passes/compute'
import { cloudFormat, createCloudLayerPass } from './passes/cloudlayer'
import { createExposurePass, exposureBufferSize } from './passes/exposure'
import { createMilkyWayPass, milkyWayFormat, milkyWaySize } from './passes/milkyway'
import { createMultiscatteringPass, multiscatteringSize } from './passes/multiscattering'
import { createNoisePass, noiseFormat, noiseSize } from './passes/noise'
import type { Pass, Targets } from './passes/pass'
import { createPostPass } from './passes/post'
import { createScenePass, sceneFormat } from './passes/scene'
import { createShaftMeanPass, shaftBlock, shaftMeanFormat } from './passes/shaftmean'
import { createShaftPass, shaftFormat } from './passes/shafts'
import { createShadowMapPass, shadowMapFormat, shadowMapSize } from './passes/shadowmap'
import { createSkyViewPass, skyViewSize } from './passes/skyview'
import { createStarsPass } from './passes/stars'
import { createTransmittancePass, transmittanceSize } from './passes/transmittance'
import { Uniforms } from './uniforms'

/** The scene is shaded at most at this many pixels and bilinearly upsampled by `post`. */
const maxScenePixels = 1.1e6

export interface Renderer {
  /** Resizes the render targets for a new output size; returns the scene resolution. */
  resize(width: number, height: number): Vec2
  render(uniforms: ArrayBuffer): void
  destroy(): void
}

export async function createRenderer({ device, context, format }: Gpu, onEdgeColors?: EdgeColors): Promise<Renderer> {
  const uniforms = device.createBuffer({
    label: 'uniforms',
    size: Uniforms.size,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })
  const exposure = device.createBuffer({
    label: 'exposure',
    size: exposureBufferSize,
    usage: GPUBufferUsage.STORAGE,
  })
  const lut = (label: string, size: GPUExtent3DDict) =>
    device.createTexture({
      label,
      size,
      format: lutFormat,
      usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
    })
  const transmittanceLut = lut('transmittance', transmittanceSize)
  const multiscatteringLut = lut('multiscattering', multiscatteringSize)
  const skyViewLut = lut('sky view', skyViewSize)
  const transmittance = transmittanceLut.createView()
  const multiscattering = multiscatteringLut.createView()
  const skyView = skyViewLut.createView({ dimension: '2d-array' })
  const noiseVolume = device.createTexture({
    label: 'cloud noise',
    size: noiseSize,
    dimension: '3d',
    format: noiseFormat,
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
  })
  const cloudNoise = noiseVolume.createView()
  const milkyWayMap = device.createTexture({
    label: 'milky way',
    size: milkyWaySize,
    format: milkyWayFormat,
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
  })
  const milkyWay = milkyWayMap.createView()
  const shadowMap = device.createTexture({
    label: 'cloud shadow',
    size: shadowMapSize,
    format: shadowMapFormat,
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
  })
  const cloudShadow = shadowMap.createView()
  const blueNoiseMask = device.createTexture({
    label: 'blue noise',
    size: [blueNoiseSize, blueNoiseSize],
    format: blueNoiseFormat,
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  })
  const jitterMask = blueNoiseMask.createView()
  const catalogue = starCatalogue()
  const storage = (label: string, data: Uint32Array<ArrayBuffer> | Float32Array<ArrayBuffer>) => {
    const buffer = device.createBuffer({ label, size: data.byteLength, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST })
    device.queue.writeBuffer(buffer, 0, data)
    return buffer
  }
  const catalogueStars = storage('catalogue', catalogue.stars)
  const catalogueCells = storage('catalogue cells', catalogue.cells)
  const catalogueEntries = storage('catalogue entries', catalogue.entries)
  const seenStars = device.createBuffer({ label: 'seen stars', size: seenStarSlots(catalogue.count) * seenStarSize, usage: GPUBufferUsage.STORAGE })
  const shared = { device, uniforms }

  const passes = Promise.all([
    createNoisePass(shared, cloudNoise),
    createMilkyWayPass(shared, milkyWay),
    createTransmittancePass(shared, transmittance),
    createMultiscatteringPass(shared, { transmittance }, multiscattering),
    createSkyViewPass(shared, { transmittance, multiscattering }, skyView),
    createExposurePass(shared, { transmittance, skyView }, exposure),
    createShadowMapPass(shared, { cloudNoise }, cloudShadow),
    createShaftPass(shared, { transmittance, cloudShadow, blueNoise: jitterMask }),
    createShaftMeanPass(shared),
    createCloudLayerPass(shared, { transmittance, skyView, cloudNoise, blueNoise: jitterMask }),
    createScenePass(shared, { transmittance, skyView, milkyWay }),
    createStarsPass(shared, { transmittance, catalogue: catalogueStars, seen: seenStars, count: catalogue.count }),
    createPostPass(shared, { exposure, catalogueCells, catalogueEntries, seen: seenStars, starCount: catalogue.count, format }),
  ])
  // Generated while the pipelines compile.
  device.queue.writeTexture({ texture: blueNoiseMask }, blueNoise(), { bytesPerRow: blueNoiseSize }, [blueNoiseSize, blueNoiseSize])
  const [noise, drawMilkyWay, ...graph]: [ComputePass, ComputePass, ...Pass[]] = await passes
  const init = device.createCommandEncoder({ label: 'init' })
  noise.encode(init)
  drawMilkyWay.encode(init)
  device.queue.submit([init.finish()])
  const edges = onEdgeColors && createEdgeSampler(device, format, onEdgeColors)

  // Everything at render scale (the cloud and shaft layers at one texel per cell), recreated on resize.
  let renderTargets: GPUTexture[] = []
  let views: Omit<Targets, 'output'> | undefined

  return {
    resize(width, height) {
      const renderScale = Math.min(1, Math.sqrt(maxScenePixels / (width * height)))
      const sceneWidth = Math.max(1, Math.round(width * renderScale))
      const sceneHeight = Math.max(1, Math.round(height * renderScale))
      const target = (label: string, format: GPUTextureFormat, cell = 1, written = GPUTextureUsage.RENDER_ATTACHMENT) =>
        device.createTexture({
          label,
          size: [Math.ceil(sceneWidth / cell), Math.ceil(sceneHeight / cell)],
          format,
          usage: written | GPUTextureUsage.TEXTURE_BINDING,
        })
      for (const texture of renderTargets) texture.destroy()
      renderTargets = [
        target('cloud layer', cloudFormat, cloudCell),
        target('cloud history', cloudFormat),
        target('cloud history', cloudFormat),
        target('light shafts', shaftFormat, cloudCell),
        target('shaft mean', shaftMeanFormat, shaftBlock, GPUTextureUsage.STORAGE_BINDING),
        target('scene', sceneFormat),
      ]
      const [clouds, history, accumulated, shafts, shaftMean, scene] = renderTargets.map((texture) => texture.createView())
      views = { clouds, history, accumulated, shafts, shaftMean, scene }
      return [sceneWidth, sceneHeight]
    },

    render(data) {
      if (!views) return
      device.queue.writeBuffer(uniforms, 0, data)
      const output = context.getCurrentTexture()
      const targets = { ...views, output: output.createView() }
      const encoder = device.createCommandEncoder({ label: 'frame' })
      for (const pass of graph) pass.encode(encoder, targets)
      edges?.encode(encoder, output)
      device.queue.submit([encoder.finish()])
      edges?.submitted()
      // What was accumulated this frame is the history of the next.
      views = { ...views, history: views.accumulated, accumulated: views.history }
    },

    destroy() {
      for (const texture of [...renderTargets, noiseVolume, milkyWayMap, shadowMap, blueNoiseMask, transmittanceLut, multiscatteringLut, skyViewLut]) {
        texture.destroy()
      }
      for (const buffer of [exposure, catalogueStars, catalogueCells, catalogueEntries, seenStars, uniforms]) buffer.destroy()
      edges?.destroy()
      context.unconfigure()
    },
  }
}
