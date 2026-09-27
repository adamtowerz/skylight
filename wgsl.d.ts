/** WGSL sources are imported as strings, through a local Turbopack loader (see next.config.ts). */
declare module '*.wgsl' {
  const source: string
  export default source
}
