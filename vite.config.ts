import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// A version per build: the commit on Vercel, otherwise a timestamp.
const version = (process.env.VERCEL_GIT_COMMIT_SHA ?? '').slice(0, 7) || new Date().toISOString().slice(0, 16).replace(/\D/g, '')

export default defineConfig({
  define: { __APP_VERSION__: JSON.stringify(version) },
  plugins: [
    react(),
    {
      // Emits the service worker with this build's version baked in.
      name: 'service-worker',
      apply: 'build',
      generateBundle() {
        const source = readFileSync('src/sw.js', 'utf8').replace('__VERSION__', version)
        this.emitFile({ type: 'asset', fileName: 'sw.js', source })
      },
    },
  ],
  server: { host: true },
})
