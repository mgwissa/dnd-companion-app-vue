<script setup lang="ts">
import { RouterLink, RouterView, useRouter } from 'vue-router'
import ThemeToggle from './components/ThemeToggle.vue'
import DndToast from './components/DndToast.vue'
import { getToastState, showToast } from './composables/useToast'
import { useAuthStore } from './stores/auth'

const auth = useAuthStore()
const router = useRouter()

async function handleLogout() {
  try {
    await auth.signOut()
    showToast('Signed out', 'info')
    router.push('/login')
  } catch {
    showToast('Sign-out failed', 'error')
  }
}
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
            <span v-if="auth.isAuthenticated" class="user-greeting">
              {{ auth.displayName }}
            </span>
            <ThemeToggle />
          </div>
        </div>

        <nav class="nav">
          <RouterLink to="/" class="nav-link">Home</RouterLink>
          <RouterLink to="/notes" class="nav-link">Notes</RouterLink>
          <RouterLink to="/links" class="nav-link">Links</RouterLink>
          <RouterLink to="/about" class="nav-link">Profile</RouterLink>
          <template v-if="auth.isAuthenticated">
            <button type="button" class="nav-link nav-btn" @click="handleLogout">
              Logout
            </button>
          </template>
          <template v-else>
            <RouterLink to="/login" class="nav-link">Login</RouterLink>
          </template>
        </nav>
      </header>

      <main class="page-wrap">
        <RouterView />
        <DndToast :toast="getToastState()" />
      </main>
    </div>
  </div>
</template>

<style scoped>
.user-greeting {
  font-size: 0.85rem;
  color: var(--banner-ink, var(--dnd-paper));
  opacity: 0.85;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 160px;
}

.nav-btn {
  background: none;
  border: none;
  font-family: inherit;
  font-size: inherit;
  cursor: pointer;
}
</style>
