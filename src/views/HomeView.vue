<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { computed, onMounted, watch } from 'vue'
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'

const auth = useAuthStore()
const campaignStore = useCampaignStore()

const activeCampaign = computed(() => campaignStore.activeCampaign)
const recentNotes = ref<{ id: string; title: string; body: string; updated_at: string }[]>([])
const party = ref<
  { id: string; character_name: string; avatar_url: string; max_hp: number; current_hp: number }[]
>([])
const openThreads = ref<{ id: string; title: string; is_done: boolean }[]>([])
const activityItems = computed(() =>
  recentNotes.value.slice(0, 5).map((note) => ({
    id: note.id,
    label: note.title || 'Untitled note',
    detail: 'Campaign note updated',
    date: note.updated_at,
  })),
)
const dashboardLoading = ref(false)
const latestSession = computed(
  () => recentNotes.value.find((note) => /session/i.test(note.title)) ?? null,
)

function hpPercent(character: (typeof party.value)[number]) {
  if (!character.max_hp) return 0
  return Math.max(0, Math.min(100, (character.current_hp / character.max_hp) * 100))
}

function formatUpdatedAt(value: string) {
  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(
    new Date(value),
  )
}

async function loadCommandCenter() {
  if (!activeCampaign.value) return
  dashboardLoading.value = true
  try {
    const campaignId = activeCampaign.value.id
    const [membersResult, notesResult, partyResult, threadsResult] = await Promise.all([
      campaignStore.fetchMembers(campaignId),
      supabase
        .from('notes')
        .select('id, title, body, updated_at')
        .eq('campaign_id', campaignId)
        .order('updated_at', { ascending: false })
        .limit(4),
      supabase
        .from('characters')
        .select('id, character_name, avatar_url, max_hp, current_hp')
        .eq('campaign_id', campaignId)
        .eq('is_active', true)
        .eq('is_npc', false)
        .order('character_name')
        .limit(6),
      supabase
        .from('campaign_threads')
        .select('id, title, is_done')
        .eq('campaign_id', campaignId)
        .eq('is_done', false)
        .order('created_at', { ascending: false })
        .limit(5),
    ])
    void membersResult
    if (notesResult.error) throw notesResult.error
    if (partyResult.error) throw partyResult.error
    if (threadsResult.error) throw threadsResult.error
    recentNotes.value = notesResult.data ?? []
    party.value = partyResult.data ?? []
    openThreads.value = threadsResult.data ?? []
  } catch (error) {
    console.warn('Failed to load campaign snapshot', error)
  } finally {
    dashboardLoading.value = false
  }
}

onMounted(loadCommandCenter)
watch(
  [() => campaignStore.activeCampaignId, () => campaignStore.campaigns.length],
  loadCommandCenter,
)
</script>

<template>
  <main v-if="auth.isAuthenticated && activeCampaign" class="command-center">
    <section class="command-hero">
      <div>
        <p class="hero-kicker">Campaign overview / active campaign</p>
        <h1 class="command-title">{{ activeCampaign.name }}</h1>
        <p class="command-subtitle">Your campaign at a glance. Pick up where the story left off.</p>
      </div>
      <div class="campaign-signal">
        <span class="signal-dot" aria-hidden="true"></span>
        <span>Campaign active</span>
      </div>
    </section>

    <section class="intel-grid" aria-label="Campaign intelligence">
      <article class="intel-card intel-card--primary">
        <span class="intel-label">Party members</span>
        <strong class="intel-value">{{ campaignStore.members.length }}</strong>
        <span class="intel-caption">registered members</span>
      </article>
      <article class="intel-card">
        <span class="intel-label">Your role</span>
        <strong class="intel-value intel-value--text">{{ campaignStore.myRole ?? 'member' }}</strong>
        <span class="intel-caption">in this campaign</span>
      </article>
      <article class="intel-card">
        <span class="intel-label">Invite code</span>
        <strong class="intel-value invite-value">{{ activeCampaign.invite_code }}</strong>
        <span class="intel-caption">share with your party</span>
      </article>
    </section>

    <section class="snapshot-grid" aria-label="Campaign snapshot">
      <article class="snapshot-panel snapshot-panel--notes">
        <div class="panel-heading">
          <div>
            <span class="panel-kicker">Latest notes</span>
            <h2>Campaign log</h2>
          </div>
          <RouterLink to="/notes" class="panel-link">View all <span aria-hidden="true">↗</span></RouterLink>
        </div>
        <div v-if="latestSession" class="session-continue">
          <span class="session-continue-label">Latest session</span>
          <strong>{{ latestSession.title }}</strong>
          <div class="session-actions">
            <RouterLink :to="{ path: '/notes', query: { note: latestSession.id } }" class="session-action session-action--primary">
              Continue session
            </RouterLink>
            <RouterLink to="/notes?start=session" class="session-action">Start new</RouterLink>
          </div>
        </div>
        <div v-if="dashboardLoading" class="panel-empty">Loading campaign notes...</div>
        <div v-else-if="recentNotes.length === 0" class="panel-empty">
          No notes yet. Start the campaign log.
        </div>
        <RouterLink
          v-for="note in recentNotes"
          :key="note.id"
          to="/notes"
          class="note-row"
        >
          <span class="note-mark" aria-hidden="true">✦</span>
          <span class="note-copy">
            <strong>{{ note.title || 'Untitled note' }}</strong>
            <span>{{ note.body?.trim() || 'No details added yet.' }}</span>
          </span>
          <time>{{ formatUpdatedAt(note.updated_at) }}</time>
        </RouterLink>
      </article>

      <article class="snapshot-panel snapshot-panel--party">
        <div class="panel-heading">
          <div>
            <span class="panel-kicker">Active characters</span>
            <h2>At the table</h2>
          </div>
          <RouterLink to="/healer" class="panel-link">Open health <span aria-hidden="true">↗</span></RouterLink>
        </div>
        <div v-if="dashboardLoading" class="panel-empty">Loading party...</div>
        <div v-else-if="party.length === 0" class="panel-empty">
          No active characters yet. Add the party to the roster.
        </div>
        <div v-else class="party-list">
          <div v-for="character in party" :key="character.id" class="party-row">
            <div class="avatar" :class="{ 'avatar--empty': !character.avatar_url }">
              <img v-if="character.avatar_url" :src="character.avatar_url" :alt="`${character.character_name} avatar`" />
              <span v-else aria-hidden="true">{{ character.character_name.charAt(0) }}</span>
            </div>
            <strong>{{ character.character_name }}</strong>
            <div class="hp-track" aria-hidden="true">
              <span :style="{ width: `${hpPercent(character)}%` }"></span>
            </div>
            <span class="hp-value">{{ character.current_hp }}/{{ character.max_hp || '?' }}</span>
          </div>
        </div>
      </article>
    </section>

    <section class="threads-snapshot" aria-labelledby="home-threads-heading">
      <div class="panel-heading">
        <div>
          <span class="panel-kicker">Between sessions</span>
          <h2 id="home-threads-heading">Open threads</h2>
        </div>
        <RouterLink to="/notes" class="panel-link">Manage threads <span aria-hidden="true">↗</span></RouterLink>
      </div>
      <div v-if="dashboardLoading" class="panel-empty">Loading open threads...</div>
      <div v-else-if="openThreads.length === 0" class="panel-empty">
        No open threads. The campaign is caught up.
      </div>
      <div v-else class="home-thread-list">
        <RouterLink v-for="thread in openThreads" :key="thread.id" to="/notes" class="home-thread">
          <span class="thread-bullet" aria-hidden="true">+</span>
          <span>{{ thread.title }}</span>
          <span class="thread-arrow" aria-hidden="true">↗</span>
        </RouterLink>
      </div>
    </section>

    <section class="activity-snapshot" aria-labelledby="activity-heading">
      <div class="panel-heading">
        <div>
          <span class="panel-kicker">Recent movement</span>
          <h2 id="activity-heading">Campaign activity</h2>
        </div>
        <RouterLink to="/notes" class="panel-link">Open notes <span aria-hidden="true">↗</span></RouterLink>
      </div>
      <div v-if="activityItems.length === 0" class="panel-empty">Your campaign activity will appear here.</div>
      <div v-else class="activity-list">
        <RouterLink v-for="item in activityItems" :key="item.id" to="/notes" class="activity-row">
          <span class="activity-dot" aria-hidden="true"></span>
          <span class="activity-copy"><strong>{{ item.label }}</strong><span>{{ item.detail }}</span></span>
          <time>{{ formatUpdatedAt(item.date) }}</time>
        </RouterLink>
      </div>
    </section>

    <section class="mission-section">
      <div class="section-heading">
        <div>
          <p class="hero-kicker">Campaign tools</p>
          <h2>Pick up the story</h2>
        </div>
        <RouterLink to="/campaigns" class="text-link">Manage campaign <span aria-hidden="true">↗</span></RouterLink>
      </div>
      <nav class="station-grid" aria-label="Campaign stations">
        <RouterLink to="/notes" class="station-card station-card--notes">
          <span class="station-code">NOTES / 01</span>
          <h3>Session notes</h3>
          <p>Record discoveries, NPCs, locations, and the details nobody wants to forget.</p>
          <span class="station-arrow" aria-hidden="true">↗</span>
        </RouterLink>
        <RouterLink to="/healer" class="station-card station-card--health">
          <span class="station-code">HEALTH / 02</span>
          <h3>Party health</h3>
          <p>Track the party, apply damage, restore HP, and keep everyone standing.</p>
          <span class="station-arrow" aria-hidden="true">↗</span>
        </RouterLink>
        <RouterLink to="/characters" class="station-card station-card--characters">
          <span class="station-code">ROSTER / 03</span>
          <h3>Character roster</h3>
          <p>Know who is at the table and keep every sheet within reach.</p>
          <span class="station-arrow" aria-hidden="true">↗</span>
        </RouterLink>
        <RouterLink to="/links" class="station-card station-card--links">
          <span class="station-code">LINKS / 04</span>
          <h3>Campaign links</h3>
          <p>Rules, sheets, maps, and every external link your campaign depends on.</p>
          <span class="station-arrow" aria-hidden="true">↗</span>
        </RouterLink>
      </nav>
    </section>
  </main>

  <main v-else class="home">
    <header class="hero">
      <p class="hero-kicker">The party's field journal</p>
      <h1 class="hero-title">Everything your campaign needs.<br /><em>Nothing it doesn't.</em></h1>
      <p class="hero-tagline">
        Keep the story moving with one calm, focused place for campaign notes, characters, links, and party health.
      </p>
    </header>

    <nav class="actions" aria-label="Main actions">
      <RouterLink to="/campaigns" class="action-card">
        <span class="action-index" aria-hidden="true">01</span>
        <div class="action-text">
          <h2 class="action-title">Campaigns</h2>
          <p class="action-desc">Create or join a campaign. Share an invite code with your party to get everyone in.</p>
        </div>
        <span class="action-arrow" aria-hidden="true">→</span>
      </RouterLink>

      <RouterLink to="/notes" class="action-card">
        <span class="action-index" aria-hidden="true">02</span>
        <div class="action-text">
          <h2 class="action-title">Notes</h2>
          <p class="action-desc">Session recaps, NPCs, locations. Keep notes private or share them with the campaign.</p>
        </div>
        <span class="action-arrow" aria-hidden="true">→</span>
      </RouterLink>

      <RouterLink to="/characters" class="action-card">
        <span class="action-index" aria-hidden="true">03</span>
        <div class="action-text">
          <h2 class="action-title">Characters</h2>
          <p class="action-desc">Create and manage your characters. Set an active one for each campaign.</p>
        </div>
        <span class="action-arrow" aria-hidden="true">→</span>
      </RouterLink>

      <RouterLink to="/healer" class="action-card">
        <span class="action-index" aria-hidden="true">04</span>
        <div class="action-text">
          <h2 class="action-title">Healer's Kit</h2>
          <p class="action-desc">Track the party's health. Heal allies, apply damage, and keep everyone alive.</p>
        </div>
        <span class="action-arrow" aria-hidden="true">→</span>
      </RouterLink>

      <RouterLink to="/links" class="action-card">
        <span class="action-index" aria-hidden="true">05</span>
        <div class="action-text">
          <h2 class="action-title">Useful links</h2>
          <p class="action-desc">Character sheet, rules, and other in-game links. One place, opens in a new tab.</p>
        </div>
        <span class="action-arrow" aria-hidden="true">→</span>
      </RouterLink>
    </nav>

    <div v-if="auth.isAuthenticated && campaignStore.activeCampaign" class="active-campaign">
      Active campaign: <strong>{{ campaignStore.activeCampaign.name }}</strong>
    </div>

    <footer class="foot-note">
      <p>Built for players. Your data is synced across devices.</p>
    </footer>
  </main>
</template>

<style scoped>
.command-center {
  max-width: 1100px;
  margin: 0 auto;
  padding: 2.5rem 2rem 4rem;
}

.command-hero {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: 2rem;
  padding: 2.25rem;
  color: #f8f5ee;
  background: linear-gradient(125deg, #242a31, #14171c 72%);
  border: 1px solid rgba(245, 198, 106, 0.28);
  border-radius: 12px;
  box-shadow: 0 16px 40px rgba(22, 25, 30, 0.28);
  position: relative;
  overflow: hidden;
}

.command-hero::after {
  content: '';
  position: absolute;
  width: 17rem;
  height: 17rem;
  right: -6rem;
  top: -8rem;
  border: 1px solid rgba(245, 198, 106, 0.18);
  transform: rotate(45deg);
}

.command-hero .hero-kicker {
  color: #f5c66a;
  margin-bottom: 0.7rem;
}

.command-title {
  font-family: 'Spectral', serif;
  font-size: clamp(2.2rem, 6vw, 4.2rem);
  line-height: 1;
  margin: 0;
  letter-spacing: -0.04em;
}

.command-subtitle {
  color: #b8bec5;
  margin: 0.8rem 0 0;
  font-size: 0.95rem;
}

.campaign-signal {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  color: #b8bec5;
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  white-space: nowrap;
  position: relative;
  z-index: 1;
}

.signal-dot {
  width: 0.55rem;
  height: 0.55rem;
  border-radius: 50%;
  background: #6dcc89;
  box-shadow: 0 0 0 5px rgba(109, 204, 137, 0.14), 0 0 16px rgba(109, 204, 137, 0.7);
}

.intel-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.75rem;
  margin: 0.75rem 0 3rem;
}

.intel-card {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  padding: 1.2rem 1.25rem;
  background: var(--dnd-elevated);
  border: 1px solid rgba(32, 36, 42, 0.11);
  border-radius: 9px;
}

.intel-card--primary {
  border-top: 3px solid var(--dnd-accent);
}

.intel-label,
.station-code {
  color: var(--dnd-accent);
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
}

.intel-value {
  font-family: 'Spectral', serif;
  font-size: 2.1rem;
  line-height: 1;
  color: var(--dnd-ink);
  margin-top: 0.45rem;
}

.intel-value--text {
  text-transform: capitalize;
  font-size: 1.55rem;
}

.invite-value {
  font-family: ui-monospace, monospace;
  font-size: 1.2rem;
  letter-spacing: 0.08em;
}

.intel-caption {
  color: var(--dnd-muted);
  font-size: 0.78rem;
}

.snapshot-grid {
  display: grid;
  grid-template-columns: 1.15fr 0.85fr;
  gap: 0.75rem;
  margin-bottom: 3rem;
}

.snapshot-panel {
  min-width: 0;
  padding: 1.35rem;
  background: var(--dnd-elevated);
  border: 1px solid rgba(32, 36, 42, 0.11);
  border-radius: 9px;
}

.snapshot-panel--notes {
  border-top: 3px solid var(--dnd-accent);
}

.snapshot-panel--party {
  border-top: 3px solid #4e8b70;
}

.threads-snapshot {
  margin-bottom: 3rem;
  padding: 1.35rem;
  background: var(--dnd-elevated);
  border: 1px solid rgba(32, 36, 42, 0.11);
  border-top: 3px solid var(--dnd-accent-2);
  border-radius: 9px;
}

.home-thread-list {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 0.45rem;
}

.home-thread {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  min-width: 0;
  padding: 0.7rem 0.75rem;
  border-radius: 6px;
  background: var(--dnd-input-bg);
  color: var(--dnd-ink);
  font-size: 0.82rem;
  transition: background 0.2s, color 0.2s;
}

.home-thread:hover {
  background: rgba(184, 134, 53, 0.14);
  color: var(--dnd-accent);
}

.activity-snapshot {
  margin-bottom: 3rem;
  padding: 1.35rem;
  background: var(--dnd-elevated);
  border: 1px solid rgba(32, 36, 42, 0.11);
  border-top: 3px solid #637b9b;
  border-radius: 9px;
}

.activity-list {
  display: flex;
  flex-direction: column;
}

.activity-row {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 0.7rem;
  padding: 0.65rem 0;
  border-top: 1px solid rgba(32, 36, 42, 0.08);
  color: var(--dnd-ink);
}

.activity-dot {
  width: 0.55rem;
  height: 0.55rem;
  border-radius: 50%;
  background: #637b9b;
  box-shadow: 0 0 0 4px rgba(99, 123, 155, 0.13);
}

.activity-copy {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  min-width: 0;
}

.activity-copy strong {
  overflow: hidden;
  font-size: 0.84rem;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.activity-copy span,
.activity-row time {
  color: var(--dnd-muted);
  font-size: 0.72rem;
}

.activity-row time {
  white-space: nowrap;
}

.home-thread > span:nth-child(2) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.thread-bullet {
  color: var(--dnd-accent-2);
  font-size: 1rem;
  font-weight: 700;
}

.thread-arrow {
  margin-left: auto;
  color: var(--dnd-accent);
}

.panel-heading {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 1rem;
}

.panel-kicker {
  color: var(--dnd-muted);
  font-size: 0.66rem;
  font-weight: 700;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}

.panel-heading h2 {
  color: var(--dnd-ink);
  font-family: 'Spectral', serif;
  font-size: 1.5rem;
  line-height: 1;
  margin: 0.25rem 0 0;
}

.panel-link {
  flex-shrink: 0;
  color: var(--dnd-accent);
  font-size: 0.76rem;
  font-weight: 700;
}

.panel-empty {
  padding: 1.25rem 0 0.5rem;
  color: var(--dnd-muted);
  font-size: 0.84rem;
}

.session-continue {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  margin-bottom: 0.6rem;
  padding: 0.75rem;
  border-radius: 7px;
  background: rgba(169, 76, 61, 0.08);
}

.session-continue-label {
  color: var(--dnd-accent);
  font-size: 0.65rem;
  font-weight: 700;
  letter-spacing: 0.13em;
  text-transform: uppercase;
}

.session-continue strong {
  color: var(--dnd-ink);
  font-family: 'Spectral', serif;
  font-size: 1.05rem;
}

.session-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-top: 0.35rem;
}

.session-action {
  color: var(--dnd-accent);
  font-size: 0.72rem;
  font-weight: 700;
}

.session-action--primary {
  padding: 0.35rem 0.55rem;
  border-radius: 5px;
  background: var(--dnd-accent);
  color: var(--dnd-on-accent);
}

.note-row {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 0.7rem;
  padding: 0.72rem 0;
  color: var(--dnd-ink);
  border-top: 1px solid rgba(32, 36, 42, 0.08);
}

.note-mark {
  color: var(--dnd-accent-2);
  font-size: 0.9rem;
}

.note-copy {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
}

.note-copy strong {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.88rem;
}

.note-copy span {
  overflow: hidden;
  color: var(--dnd-muted);
  font-size: 0.75rem;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.note-row time {
  color: var(--dnd-muted);
  font-size: 0.7rem;
  white-space: nowrap;
}

.party-list {
  display: flex;
  flex-direction: column;
}

.party-row {
  display: grid;
  grid-template-columns: 2rem minmax(5rem, 0.8fr) 1fr auto;
  align-items: center;
  gap: 0.65rem;
  padding: 0.62rem 0;
  border-top: 1px solid rgba(32, 36, 42, 0.08);
  font-size: 0.82rem;
}

.avatar {
  width: 2rem;
  height: 2rem;
  overflow: hidden;
  display: grid;
  place-items: center;
  border-radius: 50%;
  background: #d7e1db;
  color: #37694f;
  font-family: 'Spectral', serif;
  font-weight: 700;
}

.avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.hp-track {
  height: 0.35rem;
  overflow: hidden;
  border-radius: 999px;
  background: rgba(78, 139, 112, 0.15);
}

.hp-track span {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: #4e8b70;
  transition: width 0.3s ease;
}

.hp-value {
  color: var(--dnd-muted);
  font-family: ui-monospace, monospace;
  font-size: 0.68rem;
  white-space: nowrap;
}

.section-heading {
  display: flex;
  justify-content: space-between;
  align-items: end;
  gap: 1rem;
  margin-bottom: 1rem;
}

.section-heading .hero-kicker {
  margin-bottom: 0.25rem;
}

.section-heading h2 {
  color: var(--dnd-ink);
  font-family: 'Spectral', serif;
  font-size: 1.8rem;
  line-height: 1;
  margin: 0;
}

.text-link {
  color: var(--dnd-accent);
  font-size: 0.8rem;
  font-weight: 700;
}

.station-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 0.75rem;
}

.station-card {
  min-height: 220px;
  display: flex;
  flex-direction: column;
  padding: 1.25rem;
  border-radius: 9px;
  border: 1px solid rgba(32, 36, 42, 0.1);
  color: var(--dnd-ink);
  background: var(--dnd-elevated);
  position: relative;
  overflow: hidden;
  transition: transform 0.2s, border-color 0.2s, box-shadow 0.2s;
}

.station-card::before {
  content: '';
  height: 4px;
  position: absolute;
  inset: 0 0 auto;
  background: var(--station-color, var(--dnd-accent));
}

.station-card:hover {
  transform: translateY(-4px);
  border-color: var(--station-color, var(--dnd-accent));
  box-shadow: 0 14px 26px rgba(32, 36, 42, 0.12);
}

.station-card h3 {
  font-family: 'Spectral', serif;
  font-size: 1.45rem;
  margin: 2rem 0 0.55rem;
}

.station-card p {
  color: var(--dnd-muted);
  font-size: 0.83rem;
  line-height: 1.5;
  margin: 0;
}

.station-arrow {
  color: var(--station-color, var(--dnd-accent));
  font-size: 1.3rem;
  margin-top: auto;
  align-self: flex-end;
}

.station-card--notes { --station-color: #a94c3d; }
.station-card--health { --station-color: #4e8b70; }
.station-card--characters { --station-color: #b88635; }
.station-card--links { --station-color: #637b9b; }

.home {
  min-height: 70vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 4.5rem 2rem 4rem;
  max-width: 58rem;
  margin: 0 auto;
}

.hero {
  text-align: center;
  margin-bottom: 3.5rem;
  position: relative;
}

.hero::after {
  content: '';
  display: block;
  width: 3.5rem;
  height: 2px;
  margin: 2rem auto 0;
  background: var(--dnd-accent-2);
}

.hero-kicker {
  color: var(--dnd-accent);
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  margin: 0 0 1.1rem;
}

.hero-title {
  font-family: 'Spectral', serif;
  font-size: clamp(2.3rem, 6vw, 4.5rem);
  font-weight: 700;
  color: var(--dnd-ink);
  letter-spacing: -0.03em;
  margin: 0 0 0.75rem;
  line-height: 1.2;
}

.hero-title em {
  color: var(--dnd-accent);
  font-weight: 500;
}

.hero-tagline {
  font-size: 1.05rem;
  color: var(--dnd-muted);
  line-height: 1.55;
  margin: 0;
  max-width: 48ch;
  margin-inline: auto;
}

.actions {
  width: 100%;
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.8rem;
}

.action-card {
  display: flex;
  align-items: center;
  gap: 1rem;
  width: 100%;
  padding: 1.35rem 1.25rem;
  border-radius: 10px;
  background: var(--dnd-elevated);
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
  text-decoration: none;
  color: inherit;
  transition: box-shadow 0.2s ease, border-color 0.2s ease, transform 0.2s ease, background 0.2s ease;
}

.action-card:hover {
  background: var(--dnd-paper);
  box-shadow: 0 12px 30px rgba(32, 36, 42, 0.1);
  border-color: var(--dnd-accent-2);
  transform: translateY(-2px);
}

.action-card:focus-visible {
  outline: 2px solid var(--dnd-accent);
  outline-offset: 2px;
}

.action-index {
  flex-shrink: 0;
  width: 2.5rem;
  height: 2.5rem;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Spectral', serif;
  font-size: 0.85rem;
  font-weight: 700;
  color: var(--dnd-accent);
  background: rgba(169, 76, 61, 0.1);
  border-radius: 50%;
  border: 1px solid rgba(169, 76, 61, 0.22);
}

.action-text {
  flex: 1;
  min-width: 0;
}

.action-title {
  font-family: 'Spectral', serif;
  font-size: 1.125rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0 0 0.25rem;
}

.action-desc {
  font-size: 0.875rem;
  color: var(--dnd-muted);
  line-height: 1.45;
  margin: 0;
}

.action-arrow {
  flex-shrink: 0;
  font-size: 1.25rem;
  color: var(--dnd-accent);
  opacity: 0.8;
  transition: transform 0.2s ease;
}

.action-card:hover .action-arrow {
  transform: translateX(4px);
}

.active-campaign {
  margin-top: 1.5rem;
  padding: 0.75rem 1.25rem;
  background: var(--dnd-elevated);
  border: 1px solid rgba(0, 0, 0, 0.06);
  border-radius: 8px;
  font-size: 0.9rem;
  color: var(--dnd-muted);
}
.active-campaign strong {
  color: var(--dnd-ink);
}

.foot-note {
  margin-top: auto;
  padding-top: 3rem;
  text-align: center;
}

@media (max-width: 620px) {
  .command-center {
    padding: 1.25rem 1rem 3rem;
  }

  .command-hero {
    align-items: flex-start;
    flex-direction: column;
    padding: 1.5rem;
  }

  .intel-grid,
  .snapshot-grid,
  .station-grid {
    grid-template-columns: repeat(2, 1fr);
  }

  .snapshot-grid {
    grid-template-columns: 1fr;
  }

  .home {
    padding: 3rem 1rem 3rem;
  }

  .hero-title {
    font-size: clamp(2.2rem, 12vw, 3.5rem);
  }

  .actions {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 420px) {
  .intel-grid,
  .snapshot-grid,
  .station-grid {
    grid-template-columns: 1fr;
  }
}

.foot-note p {
  margin: 0;
  font-size: 0.8125rem;
  color: var(--dnd-muted);
  line-height: 1.5;
}

:global(.dark) .action-card {
  border-color: rgba(255, 255, 255, 0.1);
  box-shadow: 0 2px 14px rgba(0, 0, 0, 0.45);
}
:global(.dark) .action-card:hover {
  border-color: rgba(255, 255, 255, 0.14);
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.5);
}
:global(.dark) .action-index {
  background: rgba(255, 255, 255, 0.06);
}
:global(.dark) .active-campaign {
  border-color: rgba(255, 255, 255, 0.1);
}

@media (max-width: 380px) {
  .home {
    padding: 2rem 1rem 3rem;
  }
  .action-card {
    flex-wrap: wrap;
  }
  .action-arrow {
    margin-left: auto;
  }
}
</style>
