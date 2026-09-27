import type { Metadata, Viewport } from 'next'
import type { ReactNode } from 'react'
import './globals.css'

const title = 'Skylight'
const description = 'Lie back on the grass and watch the sky.'

// The share image comes from `opengraph-image.jpg` beside this file. Icons are listed here because
// the favicon follows the device theme: crops of the renderer's own sky, day on light tabs and
// dusk on dark.
export const metadata: Metadata = {
  title,
  description,
  icons: {
    icon: (['light', 'dark'] as const).flatMap((scheme) =>
      [32, 192].map((size) => ({
        url: `/icon-${scheme}-${size}.png`,
        sizes: `${size}x${size}`,
        type: 'image/png',
        media: `(prefers-color-scheme: ${scheme})`,
      })),
    ),
    apple: '/apple-icon.png',
  },
  // Added to the home screen, the sky runs edge to edge under a see-through status bar.
  appleWebApp: { capable: true, title, statusBarStyle: 'black-translucent' },
  openGraph: { title, description, type: 'website' },
  twitter: { card: 'summary_large_image', title, description },
}

// `viewportFit: 'cover'` lets the page draw under the notch, Dynamic Island and home indicator
// rather than inside the safe area. No theme colour: a solid one paints Safari's bars over the sky.
export const viewport: Viewport = {
  viewportFit: 'cover',
  colorScheme: 'light dark',
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
