<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { computed, onMounted, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'

const auth = useAuthStore()
const campaignStore = useCampaignStore()

const activeCampaign = computed(() => campaignStore.activeCampaign)

async function loadCommandCenter() {
  if (activeCampaign.value) {
    await campaignStore.fetchMembers(activeCampaign.value.id)
  }
}

onMounted(loadCommandCenter)
watch(() => campaignStore.activeCampaignId, loadCommandCenter)
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
  .station-grid {
    grid-template-columns: repeat(2, 1fr);
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
