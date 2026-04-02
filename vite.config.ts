import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

// https://vite.dev/config/
// GitHub Pages: app lives under /dnd-companion-app-vue/. Use Vite `command` + `mode`, not process.env.NODE_ENV
// (a global NODE_ENV=production breaks dev asset URLs).
export default defineConfig(({ command, mode }) => ({
  base:
    command === 'build' || (command === 'serve' && mode === 'production')
      ? '/dnd-companion-app-vue/'
      : '/',
  plugins: [
    vue(),
    vueDevTools(),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    },
  },
}))
