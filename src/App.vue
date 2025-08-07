<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'
import ThemeToggle from './components/ThemeToggle.vue'
</script>

<template>
  <header class="bg-white dark:bg-gray-800 shadow-sm">
    <ThemeToggle />
    <nav class="container mx-auto px-4 py-4 flex items-center justify-between">
      <div class="flex items-center space-x-4">
        <RouterLink
          to="/"
          class="text-gray-900 dark:text-white hover:text-gray-600 dark:hover:text-gray-300"
          >Home</RouterLink
        >
        <RouterLink
          to="/notes"
          class="text-gray-900 dark:text-white hover:text-gray-600 dark:hover:text-gray-300"
          >Notes</RouterLink
        >
        <RouterLink
          to="/about"
          class="text-gray-900 dark:text-white hover:text-gray-600 dark:hover:text-gray-300"
          >About</RouterLink
        >
      </div>
    </nav>
  </header>

  <RouterView class="min-h-screen bg-gray-50 dark:bg-gray-900 text-gray-900 dark:text-white" />
</template>
