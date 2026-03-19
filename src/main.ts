import './assets/main.css'

import { createApp, watch } from 'vue'
import { createPinia } from 'pinia'

import App from './App.vue'
import router from './router'

import { useThemeStore } from './stores/theme'
import { useAuthStore } from './stores/auth'

const app = createApp(App)
app.use(createPinia())
app.use(router)

const themeStore = useThemeStore()
themeStore.initTheme()

document.documentElement.classList.toggle('dark', themeStore.theme === 'dark')
document.documentElement.classList.toggle('light', themeStore.theme === 'light')

watch(
  () => themeStore.theme,
  (newTheme) => {
    document.documentElement.classList.toggle('dark', newTheme === 'dark')
    document.documentElement.classList.toggle('light', newTheme === 'light')
  },
)

const authStore = useAuthStore()
authStore.init()

app.mount('#app')
