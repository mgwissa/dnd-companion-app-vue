<script setup lang="ts">
import { RouterLink } from 'vue-router'
</script>

<template>
  <main class="home">
    <header class="hero">
      <h1 class="hero-title">DND Companion</h1>
      <p class="hero-tagline">
        Notes that actually work — for session recaps, NPCs, and everything D&D Beyond doesn’t do well.
      </p>
    </header>

    <nav class="actions" aria-label="Main actions">
      <RouterLink to="/notes" class="action-card">
        <span class="action-icon" aria-hidden="true">📜</span>
        <div class="action-text">
          <h2 class="action-title">Notes</h2>
          <p class="action-desc">Session recaps, NPCs, locations. Search, tag, export. Your data stays in your browser.</p>
        </div>
        <span class="action-arrow" aria-hidden="true">→</span>
      </RouterLink>

      <RouterLink to="/links" class="action-card">
        <span class="action-icon" aria-hidden="true">🔗</span>
        <div class="action-text">
          <h2 class="action-title">Useful links</h2>
          <p class="action-desc">Character sheet, rules, and other in-game links. One place, opens in a new tab.</p>
        </div>
        <span class="action-arrow" aria-hidden="true">→</span>
      </RouterLink>
    </nav>

    <footer class="foot-note">
      <p>Built for players. Your data is local; export to JSON anytime.</p>
    </footer>
  </main>
</template>

<style scoped>
.home {
  min-height: 60vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 3rem 1.5rem 4rem;
  max-width: 42rem;
  margin: 0 auto;
}

/* Hero: one clear headline + tagline */
.hero {
  text-align: center;
  margin-bottom: 3rem;
}

.hero-title {
  font-family: 'Cinzel', serif;
  font-size: clamp(1.875rem, 4.5vw, 2.5rem);
  font-weight: 700;
  color: var(--dnd-ink);
  letter-spacing: 0.04em;
  margin: 0 0 0.75rem;
  line-height: 1.2;
}

.hero-tagline {
  font-size: 1rem;
  color: var(--dnd-muted);
  line-height: 1.55;
  margin: 0;
  max-width: 36ch;
  margin-inline: auto;
}

/* Actions: two equal cards, full width, horizontal layout */
.actions {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.action-card {
  display: flex;
  align-items: center;
  gap: 1.25rem;
  width: 100%;
  padding: 1.5rem 1.25rem;
  border-radius: 12px;
  background: var(--dnd-paper);
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
  text-decoration: none;
  color: inherit;
  transition: box-shadow 0.2s ease, border-color 0.2s ease, transform 0.2s ease;
}

.action-card:hover {
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.08);
  border-color: rgba(0, 0, 0, 0.1);
  transform: translateY(-2px);
}

.action-card:focus-visible {
  outline: 2px solid var(--dnd-accent);
  outline-offset: 2px;
}

.action-icon {
  flex-shrink: 0;
  width: 3rem;
  height: 3rem;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.5rem;
  background: rgba(0, 0, 0, 0.04);
  border-radius: 10px;
}

.action-text {
  flex: 1;
  min-width: 0;
}

.action-title {
  font-family: 'Cinzel', serif;
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

/* Footer line */
.foot-note {
  margin-top: auto;
  padding-top: 3rem;
  text-align: center;
}

.foot-note p {
  margin: 0;
  font-size: 0.8125rem;
  color: var(--dnd-muted);
  line-height: 1.5;
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
