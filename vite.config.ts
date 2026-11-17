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
      generateBundle(_options, bundle) {
        // Every built script and stylesheet is cached on install, so screens never opened online still open offline.
        const assets = Object.keys(bundle).filter((f) => /\.(js|css)$/.test(f)).map((f) => `/${f}`)
        const source = readFileSync('src/sw.js', 'utf8').replace('__VERSION__', version).replace('[] /* __ASSETS__ */', JSON.stringify(assets))
        this.emitFile({ type: 'asset', fileName: 'sw.js', source })
      },
    },
  ],
  build: {
    rollupOptions: {
      output: {
        // Libraries in their own files: they change rarely, so they stay cached across app updates.
        manualChunks: {
          react: ['react', 'react-dom', 'react-router-dom'],
          supabase: ['@supabase/supabase-js'],
          icons: ['@hugeicons/react', '@hugeicons/core-free-icons'],
        },
      },
    },
  },
  server: { host: true },
})
