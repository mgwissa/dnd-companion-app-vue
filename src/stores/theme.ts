import { defineStore } from 'pinia'

export const useThemeStore = defineStore('theme', {
  state: () => ({
    theme: 'light' as 'light' | 'dark',
  }),
  actions: {
    initTheme() {
      // 1. Check localStorage
      const saved = localStorage.getItem('theme')
      if (saved === 'light' || saved === 'dark') {
        this.theme = saved
        return
      }

      // 2. check OS prefernce
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
      this.theme = prefersDark ? 'dark' : 'light'
    },
    toggleTheme() {
      this.theme = this.theme === 'light' ? 'dark' : 'light'
      localStorage.setItem('theme', this.theme)
    },
  },
})
