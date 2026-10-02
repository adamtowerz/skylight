/**
 * A tiny schema DSL for WGSL uniform structs. One declaration yields the WGSL `struct` text,
 * the byte layout (WGSL uniform address-space rules) and a typed writer, so TypeScript and the
 * shaders can never disagree about offsets.
 */

import type { Mat4, Vec2, Vec3, Vec4 } from './math'

/** Alignment and size in bytes, from the WGSL spec's alignment-and-size table. */
const layouts = {
  f32: { align: 4, size: 4 },
  vec2f: { align: 8, size: 8 },
  vec3f: { align: 16, size: 12 },
  vec4f: { align: 16, size: 16 },
  mat4x4f: { align: 16, size: 64 },
} as const

/** A fixed-size array of vec4f, e.g. `array<vec4f, 6>`: 16 bytes an element, as uniforms require. */
type Vec4Array = `array<vec4f, ${number}>`

export type FieldType = keyof typeof layouts | Vec4Array

interface FieldValues {
  f32: number
  vec2f: Vec2
  vec3f: Vec3
  vec4f: Vec4
  mat4x4f: Mat4
}

/** Its elements, flattened: four floats each. */
type FieldValue<T extends FieldType> = T extends keyof FieldValues ? FieldValues[T] : readonly number[]

export type Schema = Record<string, FieldType>

export type StructValues<S extends Schema> = { [K in keyof S]: FieldValue<S[K]> }

function layoutOf(type: FieldType) {
  if (type in layouts) return layouts[type as keyof typeof layouts]
  const length = Number(/^array<vec4f, (\d+)>$/.exec(type)?.[1])
  return { align: 16, size: 16 * length }
}

export interface StructWriter<S extends Schema> {
  /** Backing store, ready for `queue.writeBuffer`. */
  readonly data: ArrayBuffer
  set(values: Partial<StructValues<S>>): void
}

export interface Struct<S extends Schema> {
  readonly name: string
  /** WGSL declaration, e.g. `struct Uniforms { resolution: vec2f, ... }`. */
  readonly wgsl: string
  /** Size in bytes, rounded up to 16 as uniform buffers require. */
  readonly size: number
  create(): StructWriter<S>
}

const roundUp = (value: number, multiple: number) => Math.ceil(value / multiple) * multiple

export function struct<const S extends Schema>(name: string, schema: S): Struct<S> {
  const offsets = new Map<string, number>()
  let end = 0
  for (const [field, type] of Object.entries(schema)) {
    const { align, size } = layoutOf(type)
    const offset = roundUp(end, align)
    offsets.set(field, offset)
    end = offset + size
  }
  const size = roundUp(end, 16)

  const members = Object.entries(schema).map(([field, type]) => `  ${field}: ${type},`)
  const wgsl = `struct ${name} {\n${members.join('\n')}\n}\n`

  function create(): StructWriter<S> {
    const data = new ArrayBuffer(size)
    const floats = new Float32Array(data)
    return {
      data,
      set(values) {
        for (const field in values) {
          const value: number | readonly number[] | undefined = values[field]
          const offset = offsets.get(field)
          if (value === undefined || offset === undefined) continue
          if (typeof value === 'number') floats[offset / 4] = value
          else floats.set(value, offset / 4)
        }
      },
    }
  }

  return { name, wgsl, size, create }
}
