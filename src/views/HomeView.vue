<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'

const auth = useAuthStore()
const campaignStore = useCampaignStore()
</script>

<template>
  <main class="home">
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
