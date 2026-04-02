<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useCampaignStore } from '@/stores/campaign'
import { showToast } from '@/composables/useToast'

const route = useRoute()
const router = useRouter()
const campaignStore = useCampaignStore()

const status = ref<'joining' | 'error'>('joining')
const errorMsg = ref('')

onMounted(async () => {
  const code = route.params.code as string
  if (!code) {
    status.value = 'error'
    errorMsg.value = 'No invite code provided.'
    return
  }

  try {
    const result = await campaignStore.joinCampaign(code)
    if (result.already_member) {
      showToast(`You're already in "${result.name}"`, 'info')
    } else {
      showToast(`Joined "${result.name}"!`, 'success')
    }
    router.replace({ name: 'campaign-detail', params: { id: result.id } })
  } catch (e) {
    status.value = 'error'
    errorMsg.value = e instanceof Error ? e.message : 'Invalid or expired invite code.'
  }
})
</script>

<template>
  <main class="join-page">
    <div class="join-card">
      <template v-if="status === 'joining'">
        <h1 class="heading">Joining campaign...</h1>
        <p class="sub">Hang tight, adventurer.</p>
      </template>
      <template v-else>
        <h1 class="heading">Could not join</h1>
        <p class="error-msg">{{ errorMsg }}</p>
        <RouterLink to="/campaigns" class="btn">Go to campaigns</RouterLink>
      </template>
    </div>
  </main>
</template>

<style scoped>
.join-page {
  display: flex;
  justify-content: center;
  align-items: flex-start;
  padding: 4rem 1rem;
  min-height: 50vh;
}

.join-card {
  text-align: center;
  padding: 2.5rem 2rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.08);
  max-width: 400px;
  width: 100%;
}

.heading {
  font-family: 'Cinzel', serif;
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0 0 0.5rem;
}

.sub {
  color: var(--dnd-muted);
  margin: 0;
}

.error-msg {
  color: #b33a2a;
  margin: 0 0 1.25rem;
}

.btn {
  display: inline-block;
  padding: 0.55rem 1.25rem;
  border-radius: 8px;
  background: var(--dnd-accent);
  color: var(--dnd-on-accent);
  font-weight: 600;
  font-family: inherit;
  text-decoration: none;
  font-size: 0.9rem;
}
.btn:hover {
  filter: brightness(1.1);
}
</style>
