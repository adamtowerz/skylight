import type { Metadata, Viewport } from 'next'
import type { ReactNode } from 'react'
import './globals.css'

const title = 'Skylight'
const description = 'Lie back on the grass and watch the sky.'

// The share image comes from `opengraph-image.jpg` beside this file. Icons are listed here because
// the favicon follows the device theme — a day sky on light tabs, dusk on dark.
export const metadata: Metadata = {
  title,
  description,
  icons: {
    icon: [
      { url: '/icon-light.svg', type: 'image/svg+xml', media: '(prefers-color-scheme: light)' },
      { url: '/icon-dark.svg', type: 'image/svg+xml', media: '(prefers-color-scheme: dark)' },
    ],
    apple: '/apple-icon.png',
  },
  openGraph: { title, description, type: 'website' },
  twitter: { card: 'summary_large_image', title, description },
}

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#fff' },
    { media: '(prefers-color-scheme: dark)', color: '#000' },
  ],
  colorScheme: 'light dark',
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
