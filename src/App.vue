<script setup lang="ts">
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { onMounted, watch } from 'vue'
import ThemeToggle from './components/ThemeToggle.vue'
import DndToast from './components/DndToast.vue'
import { getToastState, showToast } from './composables/useToast'
import { useAuthStore } from './stores/auth'
import { useCampaignStore } from './stores/campaign'

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
    <div class="parallax">
      <header class="banner">
        <div class="banner-inner">
          <div class="brand">
            <RouterLink to="/" class="brand-title">DND Companion</RouterLink>
            <div class="brand-sub">Campaign tools & notes</div>
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
  border: 1px solid rgba(255, 255, 255, 0.25);
  background: rgba(0, 0, 0, 0.2);
  color: var(--banner-ink, var(--dnd-paper));
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
</style>
