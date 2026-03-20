<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useCampaignStore } from '@/stores/campaign'
import { useAuthStore } from '@/stores/auth'
import { supabase } from '@/lib/supabase'
import { showToast } from '@/composables/useToast'

interface CharacterSummary {
  id: string
  user_id: string
  character_name: string
  avatar_url: string
  is_active: boolean
}

const route = useRoute()
const router = useRouter()
const campaignStore = useCampaignStore()
const auth = useAuthStore()

const campaignId = computed(() => route.params.id as string)
const campaign = computed(() => campaignStore.campaigns.find((c) => c.id === campaignId.value))
const isOwner = computed(() => campaign.value?.created_by === auth.user?.id)
const loading = ref(true)
const characters = ref<CharacterSummary[]>([])
const copied = ref(false)

async function load() {
  loading.value = true
  try {
    if (campaignStore.campaigns.length === 0) await campaignStore.fetchCampaigns()
    campaignStore.setActiveCampaign(campaignId.value)
    await campaignStore.fetchMembers(campaignId.value)

    const { data } = await supabase
      .from('characters')
      .select('id, user_id, character_name, avatar_url, is_active')
      .eq('campaign_id', campaignId.value)
    characters.value = (data ?? []) as CharacterSummary[]
  } finally {
    loading.value = false
  }
}

onMounted(load)
watch(campaignId, load)

function activeCharacterFor(userId: string): CharacterSummary | undefined {
  return characters.value.find((c) => c.user_id === userId && c.is_active)
}

function memberDisplayName(member: { user_id: string; display_name?: string; email?: string }) {
  return member.display_name || member.email || member.user_id.slice(0, 8)
}

async function copyInviteCode() {
  if (!campaign.value) return
  try {
    const url = `${window.location.origin}${import.meta.env.BASE_URL}join/${campaign.value.invite_code}`
    await navigator.clipboard.writeText(url)
    copied.value = true
    showToast('Invite link copied!', 'success')
    setTimeout(() => (copied.value = false), 2000)
  } catch {
    await navigator.clipboard.writeText(campaign.value.invite_code)
    copied.value = true
    showToast('Invite code copied!', 'success')
    setTimeout(() => (copied.value = false), 2000)
  }
}

async function handleRemoveMember(memberId: string) {
  try {
    await campaignStore.removeMember(memberId)
    showToast('Member removed', 'info')
  } catch {
    showToast('Failed to remove member', 'error')
  }
}

async function handleDelete() {
  if (!confirm('Delete this campaign? This will remove all members, characters, and notes tied to it.')) return
  try {
    await campaignStore.deleteCampaign(campaignId.value)
    showToast('Campaign deleted', 'info')
    router.push({ name: 'campaigns' })
  } catch {
    showToast('Failed to delete campaign', 'error')
  }
}

async function handleLeave() {
  try {
    await campaignStore.leaveCampaign(campaignId.value)
    showToast('Left campaign', 'info')
    router.push({ name: 'campaigns' })
  } catch {
    showToast('Failed to leave campaign', 'error')
  }
}
</script>

<template>
  <main class="detail-page">
    <div v-if="loading" class="loading">Loading campaign...</div>
    <div v-else-if="!campaign" class="loading">Campaign not found.</div>

    <template v-else>
      <header class="detail-header">
        <h1 class="campaign-title">{{ campaign.name }}</h1>
        <div class="invite-section">
          <span class="invite-label">Invite code:</span>
          <code class="invite-code">{{ campaign.invite_code }}</code>
          <button class="btn btn-sm" @click="copyInviteCode">
            {{ copied ? 'Copied!' : 'Copy link' }}
          </button>
        </div>
      </header>

      <section class="members-section">
        <h2 class="section-heading">Members</h2>
        <ul class="members-list">
          <li v-for="m in campaignStore.members" :key="m.id" class="member-row">
            <div class="member-info">
              <span class="member-name">
                {{ memberDisplayName(m) }}
                <span v-if="m.role === 'owner'" class="role-badge">DM</span>
              </span>
              <span v-if="activeCharacterFor(m.user_id)" class="member-character">
                Playing: {{ activeCharacterFor(m.user_id)!.character_name || 'Unnamed' }}
              </span>
              <span v-else class="member-character member-character--none">No active character</span>
            </div>
            <div class="member-actions">
              <button
                v-if="isOwner && m.user_id !== auth.user?.id"
                class="btn-icon danger"
                title="Remove member"
                @click="handleRemoveMember(m.id)"
              >
                Remove
              </button>
            </div>
          </li>
        </ul>
      </section>

      <div class="detail-actions">
        <RouterLink :to="{ name: 'about' }" class="btn btn-secondary">
          Manage characters
        </RouterLink>
        <button
          v-if="isOwner"
          class="btn btn-danger"
          @click="handleDelete"
        >
          Delete campaign
        </button>
        <button
          v-if="!isOwner"
          class="btn btn-danger"
          @click="handleLeave"
        >
          Leave campaign
        </button>
      </div>
    </template>
  </main>
</template>

<style scoped>
.detail-page {
  padding: 3rem 1rem 4rem;
  max-width: 600px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 2rem;
}

.loading {
  text-align: center;
  color: var(--dnd-muted);
  padding: 3rem 0;
}

.detail-header {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  padding: 1.5rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.08);
}

.campaign-title {
  font-family: 'Cinzel', serif;
  font-size: 1.75rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
}

.invite-section {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
}

.invite-label {
  font-size: 0.85rem;
  color: var(--dnd-muted);
}

.invite-code {
  font-family: ui-monospace, monospace;
  font-size: 0.95rem;
  background: rgba(0, 0, 0, 0.05);
  padding: 0.2rem 0.5rem;
  border-radius: 6px;
  color: var(--dnd-ink);
}

.section-heading {
  font-family: 'Cinzel', serif;
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0 0 0.75rem;
}

.members-section {
  padding: 1.5rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
}

.members-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.member-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.75rem;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.06);
}

.member-info {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.member-name {
  font-weight: 600;
  font-size: 0.95rem;
  color: var(--dnd-ink);
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

.role-badge {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  background: var(--dnd-accent);
  color: var(--dnd-paper);
  padding: 0.1rem 0.35rem;
  border-radius: 4px;
}

.member-character {
  font-size: 0.8rem;
  color: var(--dnd-muted);
}
.member-character--none {
  font-style: italic;
}

.member-actions {
  flex-shrink: 0;
}

.detail-actions {
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
}

.btn {
  padding: 0.55rem 1rem;
  border-radius: 8px;
  border: none;
  font-weight: 600;
  font-family: inherit;
  font-size: 0.9rem;
  cursor: pointer;
  text-decoration: none;
  transition: filter 0.15s;
}
.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.btn-sm {
  padding: 0.3rem 0.6rem;
  font-size: 0.8rem;
  background: var(--dnd-accent-2);
  color: var(--dnd-paper);
  border: none;
  border-radius: 6px;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
}
.btn-sm:hover {
  filter: brightness(1.08);
}
.btn-secondary {
  background: var(--dnd-accent-2);
  color: var(--dnd-paper);
}
.btn-secondary:hover {
  filter: brightness(1.08);
}
.btn-danger {
  background: #b33a2a;
  color: #fff;
}
.btn-danger:hover {
  filter: brightness(1.1);
}
.btn-icon {
  padding: 0.3rem 0.5rem;
  border: none;
  background: transparent;
  font-size: 0.8rem;
  cursor: pointer;
  border-radius: 6px;
  font-family: inherit;
  color: var(--dnd-muted);
}
.btn-icon.danger:hover {
  background: rgba(179, 58, 42, 0.12);
  color: #b33a2a;
}
</style>
