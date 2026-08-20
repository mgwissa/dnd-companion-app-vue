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
        <p class="detail-kicker">Campaign dossier / {{ isOwner ? 'owner view' : 'member view' }}</p>
        <h1 class="campaign-title">{{ campaign.name }}</h1>
        <p class="detail-subtitle">Your shared table, party roster, and invite access in one place.</p>
        <div class="invite-section">
          <span class="invite-label">Invite code</span>
          <code class="invite-code">{{ campaign.invite_code }}</code>
          <button class="btn btn-sm" @click="copyInviteCode">
            {{ copied ? 'Copied' : 'Copy invite link' }}
          </button>
        </div>
      </header>

      <section class="members-section">
        <div class="section-heading-row">
          <div>
            <p class="section-kicker">Party roster</p>
            <h2 class="section-heading">Members</h2>
          </div>
          <span class="member-count">{{ campaignStore.members.length }} {{ campaignStore.members.length === 1 ? 'member' : 'members' }}</span>
        </div>
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
  padding: 2.5rem 2rem 4rem;
  max-width: 840px;
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
  padding: 2rem;
  background: linear-gradient(125deg, #242a31, #14171c 72%);
  border-radius: 10px;
  border: 1px solid rgba(245, 198, 106, 0.28);
  color: #f8f5ee;
  position: relative;
  overflow: hidden;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.08);
}

.campaign-title {
  font-family: 'Spectral', serif;
  font-size: clamp(2.2rem, 5vw, 3.6rem);
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
  letter-spacing: -0.04em;
}

.detail-kicker,
.section-kicker {
  color: #f5c66a;
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  margin: 0 0 0.55rem;
}

.detail-subtitle {
  color: #b8bec5;
  font-size: 0.9rem;
  margin: 0.6rem 0 1.5rem;
}

.invite-section {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
  padding-top: 1rem;
  border-top: 1px solid rgba(255, 255, 255, 0.14);
}

.invite-label {
  font-size: 0.85rem;
  color: #b8bec5;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.invite-code {
  font-family: ui-monospace, monospace;
  font-size: 0.95rem;
  background: rgba(255, 255, 255, 0.09);
  padding: 0.2rem 0.5rem;
  border-radius: 6px;
  color: #f8f5ee;
}

.section-heading {
  font-family: 'Spectral', serif;
  font-size: 1.6rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0 0 0.75rem;
}

.members-section {
  padding: 1.5rem;
  background: var(--dnd-elevated);
  border-radius: 10px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
  border-top: 3px solid #637b9b;
}

.section-heading-row {
  display: flex;
  justify-content: space-between;
  align-items: end;
  gap: 1rem;
  margin-bottom: 1rem;
}

.section-kicker {
  color: var(--dnd-accent);
  margin-bottom: 0.2rem;
}

.section-heading-row .section-heading { margin: 0; }

.member-count {
  color: var(--dnd-muted);
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
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
  padding: 0.9rem;
  border-radius: 8px;
  border: 1px solid rgba(32, 36, 42, 0.1);
  background: var(--dnd-input-bg);
}

.member-info {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.member-name {
  font-weight: 600;
  font-family: 'Spectral', serif;
  font-size: 1.05rem;
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
  color: var(--dnd-on-accent);
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
  color: var(--dnd-on-accent);
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
  color: var(--dnd-on-accent);
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

@media (max-width: 600px) {
  .detail-page {
    padding: 1.25rem 1rem 3rem;
  }

  .detail-header,
  .members-section {
    padding: 1.25rem;
  }

  .section-heading-row {
    align-items: flex-start;
    flex-direction: column;
  }

  .member-row {
    align-items: flex-start;
  }
}
</style>
