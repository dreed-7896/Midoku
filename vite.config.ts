import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// In dev (Codespace), Suwayomi is on localhost:4567 — proxy /api to it.
export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    proxy: { '/api': process.env.SUWAYOMI_URL ?? 'http://localhost:4567' },
  },
})
