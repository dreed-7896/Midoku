// Renders the PWA PNG icons from public/icon.svg. Skips quietly if sharp is unavailable.
import { mkdirSync, readFileSync } from 'node:fs'

try {
  const { default: sharp } = await import('sharp')
  const svg = readFileSync('public/icon.svg')
  mkdirSync('public/icons', { recursive: true })
  for (const [name, size] of [['icon-192.png', 192], ['icon-512.png', 512], ['apple-touch-icon.png', 180]]) {
    await sharp(svg).resize(size, size).png().toFile(`public/icons/${name}`)
  }
  // iOS app shell icon: 1024 px, no transparency
  await sharp(svg).resize(1024, 1024).flatten({ background: '#09090b' }).png()
    .toFile('ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png').catch(() => {})
  console.log('icons: generated')
} catch (err) {
  console.warn('icons: skipped —', err.message)
}
