import { defineConfig } from 'vite';

// Three pages: the main window, the check-in popup that drops in at the top of the screen, and the glow behind it.
export default defineConfig({
  clearScreen: false,
  server: { port: 1420, strictPort: true, fs: { allow: ['..'] } }, // shared/ lives next to windows/
  build: {
    target: 'es2022',
    rollupOptions: { input: { main: 'index.html', checkin: 'checkin.html', aurora: 'aurora.html' } },
  },
});
