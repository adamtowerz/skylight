/** Turbopack loader: a `.wgsl` file becomes a module whose default export is its source. */
module.exports = function wgslLoader(source) {
  return `export default ${JSON.stringify(source)}`
}
