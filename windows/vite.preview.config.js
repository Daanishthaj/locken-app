// Preview build for checking the UI in a browser (fake user, no Tauri). `npx vite build -c vite.preview.config.js`.
import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';
const mock = (name) => fileURLToPath(new URL(`./preview/mocks/${name}`, import.meta.url));
export default defineConfig({
  resolve: {
    alias: {
      '@tauri-apps/api/core': mock('core.js'),
      '@tauri-apps/api/event': mock('event.js'),
      '@tauri-apps/api/window': mock('window.js'),
      '@tauri-apps/plugin-opener': mock('opener.js'),
      '@tauri-apps/plugin-deep-link': mock('deep-link.js'),
    },
  },
  worker: { format: 'es' },
  plugins: [{ name: 'preview-entry', transformIndexHtml: { order: 'pre', handler: (html) => html.replace('/src/main.js', '/preview/entry.js') } }],
  build: { outDir: 'dist-preview', emptyOutDir: true, target: 'es2022', rollupOptions: { input: { main: 'index.html', checkin: 'checkin.html' } } },
});
