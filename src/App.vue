<script setup lang="ts">
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { onMounted, watch } from 'vue'
import ThemeToggle from './components/ThemeToggle.vue'
import DndToast from './components/DndToast.vue'
import { getToastState, showToast } from './composables/useToast'
import { isSupabaseConfigured } from '@/lib/supabase'
import { useAuthStore } from './stores/auth'
import { useCampaignStore } from './stores/campaign'

const showSupabaseDevHint = import.meta.env.DEV && !isSupabaseConfigured

const logoUrl = `${import.meta.env.BASE_URL}logo.svg`

const auth = useAuthStore()
const campaignStore = useCampaignStore()
const router = useRouter()

onMounted(() => {
  if (auth.isAuthenticated) campaignStore.fetchCampaigns()
})

watch(
  () => auth.isAuthenticated,
  (authed) => {
    if (authed) campaignStore.fetchCampaigns()
    else campaignStore.reset()
  },
)

function onCampaignChange(e: Event) {
  const val = (e.target as HTMLSelectElement).value
  if (val === '__manage__') {
    router.push({ name: 'campaigns' })
    return
  }
  campaignStore.setActiveCampaign(val || null)
}

async function handleLogout() {
  try {
    await auth.signOut()
    campaignStore.reset()
    showToast('Signed out', 'info')
    router.push('/login')
  } catch {
    showToast('Sign-out failed', 'error')
  }
}
</script>

<template>
  <div class="site-root">
    <div v-if="showSupabaseDevHint" class="dev-env-banner" role="status">
      Add <code>.env.local</code> with <code>VITE_SUPABASE_URL</code> and
      <code>VITE_SUPABASE_ANON_KEY</code> to enable login and synced data.
    </div>
    <div class="app-shell">
      <header class="banner">
        <div class="banner-inner">
          <div class="brand">
            <RouterLink to="/" class="brand-link">
              <img
                :src="logoUrl"
                width="40"
                height="40"
                class="brand-logo"
                alt=""
              />
              <span class="brand-text">
                <span class="brand-title">TTRPG Companion</span>
                <span class="brand-sub">Campaign & session tools</span>
              </span>
            </RouterLink>
          </div>
          <div class="controls">
            <select
              v-if="auth.isAuthenticated && campaignStore.campaigns.length > 0"
              class="campaign-select"
              :value="campaignStore.activeCampaignId ?? ''"
              @change="onCampaignChange"
            >
              <option value="" disabled>Select campaign</option>
              <option
                v-for="c in campaignStore.campaigns"
                :key="c.id"
                :value="c.id"
              >
                {{ c.name }}
              </option>
              <option value="__manage__">Manage campaigns...</option>
            </select>
            <span v-if="auth.isAuthenticated" class="user-greeting">
              {{ auth.displayName }}
            </span>
            <ThemeToggle />
          </div>
        </div>

        <nav class="nav">
          <RouterLink to="/" class="nav-link">Home</RouterLink>
          <template v-if="auth.isAuthenticated">
            <RouterLink to="/campaigns" class="nav-link">Campaigns</RouterLink>
            <RouterLink to="/notes" class="nav-link">Notes</RouterLink>
            <RouterLink to="/links" class="nav-link">Links</RouterLink>
            <RouterLink to="/characters" class="nav-link">Characters</RouterLink>
            <RouterLink to="/healer" class="nav-link">Healer's Kit</RouterLink>
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
.dev-env-banner {
  padding: 0.6rem 1rem;
  text-align: center;
  font-size: 0.85rem;
  font-family: system-ui, sans-serif;
  background: #3d2914;
  color: #f5e6c8;
  border-bottom: 1px solid rgba(255, 255, 255, 0.12);
}
.dev-env-banner code {
  font-size: 0.8em;
  padding: 0.1em 0.35em;
  border-radius: 4px;
  background: rgba(0, 0, 0, 0.25);
}

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

.campaign-select {
  padding: 0.3rem 0.5rem;
  border-radius: 6px;
  font-family: inherit;
  font-size: 0.82rem;
  cursor: pointer;
  max-width: 160px;
}
.campaign-select:focus {
  outline: 2px solid var(--dnd-accent);
  outline-offset: 2px;
}
.campaign-select option {
  background: var(--dnd-paper);
  color: var(--dnd-ink);
}

.brand-link {
  display: flex;
  align-items: center;
  gap: 0.65rem;
  text-decoration: none;
  color: inherit;
  min-width: 0;
}

.brand-logo {
  width: 40px;
  height: 40px;
  flex-shrink: 0;
  border-radius: 10px;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.12);
}

.brand-text {
  display: flex;
  flex-direction: column;
  gap: 0.05rem;
  min-width: 0;
}

.brand-text .brand-title {
  display: block;
}

.brand-text .brand-sub {
  display: block;
}
</style>
