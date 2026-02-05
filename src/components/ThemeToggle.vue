<script setup lang="ts">
import { useThemeStore } from '@/stores/theme'
import { MoonIcon, SunIcon } from '@heroicons/vue/24/solid'
import { computed } from 'vue'

const themeStore = useThemeStore()
const isLight = computed({
  get: () => themeStore.theme === 'light',
  set: (v: boolean) => {
    themeStore.theme = v ? 'light' : 'dark'
    localStorage.setItem('theme', themeStore.theme)
  },
})
</script>

<template>
  <div class="theme-toggle-wrapper">
    <MoonIcon class="toggle-icon" :style="{ opacity: isLight ? 0.4 : 1 }" />
    <label class="switch">
      <input type="checkbox" v-model="isLight" />
      <span class="slider round"></span>
    </label>
    <SunIcon class="toggle-icon" :style="{ opacity: isLight ? 1 : 0.4 }" />
  </div>
</template>

<style scoped>
.theme-toggle-wrapper {
  display: flex;
  width: 150px;
  align-items: center;
}

.toggle-icon {
  color: var(--banner-ink);
  width: 24px;
  height: 24px;
}

.slider-container {
  background-color: transparent;
  border: none;
}

/* The switch - the box around the slider */
.switch {
  position: relative;
  display: inline-block;
  width: 60px;
  height: 34px;
}

/* Hide default HTML checkbox */
.switch input {
  opacity: 0;
  width: 0;
  height: 0;
}

/* The slider */
.slider {
  position: absolute;
  cursor: pointer;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: #ccc;
  -webkit-transition: 0.4s;
  transition: 0.4s;
}

.slider:before {
  position: absolute;
  content: '';
  height: 26px;
  width: 26px;
  left: 4px;
  bottom: 4px;
  background-color: white;
  -webkit-transition: 0.4s;
  transition: 0.4s;
}

input:checked + .slider {
  background-color: hsla(160, 100%, 37%, 1);
}

input:focus + .slider {
  box-shadow: 0 0 1px hsla(160, 100%, 37%, 1);
}

input:checked + .slider:before {
  -webkit-transform: translateX(26px);
  -ms-transform: translateX(26px);
  transform: translateX(26px);
}

/* Rounded sliders */
.slider.round {
  border-radius: 34px;
}

.slider.round:before {
  border-radius: 50%;
}
</style>
