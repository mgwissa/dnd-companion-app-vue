<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'
import ThemeToggle from './components/ThemeToggle.vue'
import DndToast from './components/DndToast.vue'
import { getToastState } from './composables/useToast'
</script>

<template>
  <div class="site-root">
    <div class="parallax">
      <header class="banner">
        <div class="banner-inner">
          <div class="brand">
            <RouterLink to="/" class="brand-title">DND Companion</RouterLink>
            <div class="brand-sub">Campaign tools & notes</div>
          </div>
          <div class="controls">
            <ThemeToggle />
          </div>
        </div>

        <nav class="nav">
          <RouterLink to="/" class="nav-link">Home</RouterLink>
          <RouterLink to="/notes" class="nav-link">Notes</RouterLink>
          <RouterLink to="/about" class="nav-link">About</RouterLink>
          <RouterLink to="/login" class="nav-link">Login</RouterLink>
        </nav>
      </header>

      <main class="page-wrap">
        <RouterView />
        <!-- global toast mounted at app root -->
        <DndToast :toast="getToastState()" />
      </main>
    </div>
  </div>
</template>
