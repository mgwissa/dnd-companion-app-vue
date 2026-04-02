<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useCampaignStore } from '@/stores/campaign'
import { showToast } from '@/composables/useToast'

const campaign = useCampaignStore()
const router = useRouter()

const newName = ref('')
const joinCode = ref('')
const creating = ref(false)
const joining = ref(false)

onMounted(() => campaign.fetchCampaigns())

async function handleCreate() {
  const name = newName.value.trim()
  if (!name) {
    showToast('Campaign name is required', 'error')
    return
  }
  creating.value = true
  try {
    const c = await campaign.createCampaign(name)
    newName.value = ''
    showToast('Campaign created!', 'success')
    router.push({ name: 'campaign-detail', params: { id: c.id } })
  } catch (e) {
    showToast(e instanceof Error ? e.message : 'Failed to create campaign', 'error')
  } finally {
    creating.value = false
  }
}

async function handleJoin() {
  const code = joinCode.value.trim()
  if (!code) {
    showToast('Enter an invite code', 'error')
    return
  }
  joining.value = true
  try {
    const result = await campaign.joinCampaign(code)
    joinCode.value = ''
    if (result.already_member) {
      showToast('You are already in this campaign', 'info')
    } else {
      showToast(`Joined "${result.name}"!`, 'success')
    }
    router.push({ name: 'campaign-detail', params: { id: result.id } })
  } catch (e) {
    showToast(e instanceof Error ? e.message : 'Invalid invite code', 'error')
  } finally {
    joining.value = false
  }
}

function selectCampaign(id: string) {
  campaign.setActiveCampaign(id)
  router.push({ name: 'campaign-detail', params: { id } })
}
</script>

<template>
  <main class="campaigns-page">
    <h1 class="page-title">Your Campaigns</h1>

    <div class="actions-row">
      <section class="action-card">
        <h2 class="card-heading">Create a campaign</h2>
        <div class="card-form">
          <input
            v-model="newName"
            type="text"
            class="input"
            placeholder="Campaign name"
            @keydown.enter="handleCreate"
          />
          <button class="btn btn-primary" :disabled="creating" @click="handleCreate">
            {{ creating ? 'Creating...' : 'Create' }}
          </button>
        </div>
      </section>

      <section class="action-card">
        <h2 class="card-heading">Join a campaign</h2>
        <div class="card-form">
          <input
            v-model="joinCode"
            type="text"
            class="input"
            placeholder="Invite code"
            @keydown.enter="handleJoin"
          />
          <button class="btn btn-primary" :disabled="joining" @click="handleJoin">
            {{ joining ? 'Joining...' : 'Join' }}
          </button>
        </div>
      </section>
    </div>

    <section class="campaigns-list-section">
      <div v-if="campaign.loading" class="empty">Loading campaigns...</div>
      <div v-else-if="campaign.campaigns.length === 0" class="empty">
        <p>No campaigns yet. Create one or join with an invite code above.</p>
      </div>
      <ul v-else class="campaigns-grid">
        <li
          v-for="c in campaign.campaigns"
          :key="c.id"
          class="campaign-card"
          :class="{ 'campaign-card--active': c.id === campaign.activeCampaignId }"
        >
          <button class="campaign-card-btn" @click="selectCampaign(c.id)">
            <span class="campaign-name">{{ c.name }}</span>
            <span class="campaign-meta">
              Code: <code class="invite-code">{{ c.invite_code }}</code>
            </span>
          </button>
        </li>
      </ul>
    </section>
  </main>
</template>

<style scoped>
.campaigns-page {
  padding: 3rem 1rem 4rem;
  max-width: 700px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 2rem;
}

.page-title {
  font-family: 'Cinzel', serif;
  font-size: 1.75rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
}

.actions-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
}

.action-card {
  padding: 1.25rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
}

.card-heading {
  font-family: 'Cinzel', serif;
  font-size: 1rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0 0 0.75rem;
}

.card-form {
  display: flex;
  gap: 0.5rem;
}

.input {
  flex: 1;
  padding: 0.5rem 0.75rem;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.12);
  background: var(--dnd-bg);
  color: var(--dnd-ink);
  font-size: 0.95rem;
  font-family: inherit;
}
.input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.15);
}
.input::placeholder {
  color: var(--dnd-muted);
}

.btn {
  padding: 0.5rem 1rem;
  border-radius: 8px;
  border: none;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  font-size: 0.9rem;
  transition: filter 0.15s, opacity 0.15s;
}
.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.btn-primary {
  background: var(--dnd-accent);
  color: var(--dnd-on-accent);
}
.btn-primary:hover:not(:disabled) {
  filter: brightness(1.1);
}

.empty {
  text-align: center;
  color: var(--dnd-muted);
  padding: 2rem;
  font-size: 0.95rem;
}
.empty p {
  margin: 0;
}

.campaigns-grid {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 1rem;
}

.campaign-card {
  border-radius: 10px;
  border: 1px solid rgba(0, 0, 0, 0.08);
  background: var(--dnd-paper);
  transition: border-color 0.15s, box-shadow 0.15s;
}
.campaign-card:hover {
  border-color: rgba(0, 0, 0, 0.16);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
}
.campaign-card--active {
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 2px rgba(139, 58, 47, 0.15);
}

.campaign-card-btn {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 1.25rem;
  width: 100%;
  border: none;
  background: none;
  color: inherit;
  font-family: inherit;
  text-align: start;
  cursor: pointer;
  border-radius: 10px;
}
.campaign-card-btn:focus-visible {
  outline: 2px solid var(--dnd-accent);
  outline-offset: 2px;
}

.campaign-name {
  font-family: 'Cinzel', serif;
  font-weight: 700;
  font-size: 1.05rem;
  color: var(--dnd-ink);
}

.campaign-meta {
  font-size: 0.8rem;
  color: var(--dnd-muted);
}

.invite-code {
  font-family: ui-monospace, monospace;
  background: rgba(0, 0, 0, 0.05);
  padding: 0.1rem 0.3rem;
  border-radius: 4px;
}

@media (max-width: 500px) {
  .actions-row {
    grid-template-columns: 1fr;
  }
  .card-form {
    flex-direction: column;
  }
}
</style>
