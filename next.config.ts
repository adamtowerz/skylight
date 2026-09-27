import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  experimental: {
    // Styles arrive with the HTML, so the blank first paint never waits on a stylesheet.
    inlineCss: true,
  },
  turbopack: {
    // Shaders are plain `.wgsl` files imported as strings. A local loader, because the built-in
    // `{ type: 'raw' }` rule yields an empty module in Next 16.3.
    rules: { '*.wgsl': { loaders: ['./scripts/wgsl-loader.cjs'], as: '*.js' } },
  },
}

export default nextConfig
