import { defineConfig } from 'vite'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import path from 'node:path'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// `vite preview` serves the same security headers as Vercel (vercel.json is the single source), so the CSP
// can be tested locally before it ships.
const vercelHeaders = JSON.parse(readFileSync(path.resolve(__dirname, 'vercel.json'), 'utf8'))
  .headers.find((rule) => rule.source === '/(.*)').headers
const previewHeaders = Object.fromEntries(vercelHeaders.map(({ key, value }) => [key, value]))

// https://vite.dev/config/
export default defineConfig({
  plugins: [tailwindcss(), react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    strictPort: true,
    host: true,
  },
  preview: {
    port: 4173,
    strictPort: true,
    headers: previewHeaders,
  },
})
