<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'
import { showToast } from '@/composables/useToast'

interface PartyCharacter {
  id: string
  user_id: string
  character_name: string
  avatar_url: string
  max_hp: number
  current_hp: number
  temp_hp: number
  is_active: boolean
  is_npc: boolean
}

const auth = useAuthStore()
const campaignStore = useCampaignStore()

const characters = ref<PartyCharacter[]>([])
const loading = ref(true)
const hpAmounts = ref<Record<string, number>>({})

const maxHpEditing = ref<string | null>(null)
const maxHpInput = ref(0)

const tempHpEditing = ref<string | null>(null)
const tempHpInput = ref(0)

const addName = ref('')
const addMaxHp = ref<number | null>(null)
const adding = ref(false)

const campaignId = computed(() => campaignStore.activeCampaignId)
const campaignName = computed(() => campaignStore.activeCampaign?.name ?? 'Campaign')

async function fetchParty() {
  if (!campaignId.value) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('characters')
      .select('id, user_id, character_name, avatar_url, max_hp, current_hp, temp_hp, is_active, is_npc')
      .eq('campaign_id', campaignId.value)
      .eq('is_active', true)
      .order('character_name')
    if (error) throw error
    characters.value = data as PartyCharacter[]
    for (const c of characters.value) {
      if (!(c.id in hpAmounts.value)) hpAmounts.value[c.id] = 0
    }
  } catch (e) {
    console.warn('Failed to fetch party', e)
    showToast('Failed to load party', 'error')
  } finally {
    loading.value = false
  }
}

onMounted(fetchParty)
watch(campaignId, fetchParty)

// ---- HP helpers ----

function hpPercent(c: PartyCharacter): number {
  if (c.max_hp <= 0) return 100
  return Math.max(0, Math.min(100, (c.current_hp / c.max_hp) * 100))
}

function hpBarClass(c: PartyCharacter): string {
  if (c.max_hp <= 0) return 'hp-bar-fill--unset'
  const pct = hpPercent(c)
  if (c.current_hp <= 0) return 'hp-bar-fill--dead'
  if (pct <= 25) return 'hp-bar-fill--critical'
  if (pct <= 50) return 'hp-bar-fill--bloodied'
  return 'hp-bar-fill--healthy'
}

function cardClass(c: PartyCharacter): Record<string, boolean> {
  if (c.max_hp <= 0) return {}
  const pct = hpPercent(c)
  return {
    'char-card--down': c.current_hp <= 0,
    'char-card--critical': c.current_hp > 0 && pct <= 25,
    'char-card--bloodied': c.current_hp > 0 && pct > 25 && pct <= 50,
    'char-card--healthy': c.current_hp > 0 && pct > 50,
  }
}

function statusLabel(c: PartyCharacter): string {
  if (c.max_hp <= 0) return 'No HP set'
  if (c.current_hp <= 0) return 'Down!'
  const pct = hpPercent(c)
  if (pct <= 25) return 'Critical'
  if (pct <= 50) return 'Bloodied'
  if (pct >= 100) return 'Full health'
  return 'Healthy'
}

function statusClass(c: PartyCharacter): string {
  if (c.max_hp <= 0) return 'status--unset'
  if (c.current_hp <= 0) return 'status--dead'
  const pct = hpPercent(c)
  if (pct <= 25) return 'status--critical'
  if (pct <= 50) return 'status--bloodied'
  return 'status--healthy'
}

// ---- RPC wrapper ----

async function updateHp(c: PartyCharacter, newHp: number, newMax?: number, newTemp?: number) {
  try {
    const params: Record<string, unknown> = {
      p_character_id: c.id,
      p_current_hp: newHp,
    }
    if (newMax !== undefined) params.p_max_hp = newMax
    if (newTemp !== undefined) params.p_temp_hp = newTemp

    const { error } = await supabase.rpc('update_character_hp', params)
    if (error) throw error

    const idx = characters.value.findIndex((x) => x.id === c.id)
    if (idx !== -1) {
      characters.value[idx].current_hp = newHp
      if (newMax !== undefined) characters.value[idx].max_hp = newMax
      if (newTemp !== undefined) characters.value[idx].temp_hp = newTemp
    }
  } catch (e) {
    console.warn('Failed to update HP', e)
    showToast('Failed to update HP', 'error')
  }
}

// ---- Actions ----

async function heal(c: PartyCharacter) {
  const amount = hpAmounts.value[c.id] || 0
  if (amount <= 0) return
  const cap = c.max_hp > 0 ? c.max_hp : Infinity
  const newHp = Math.min(cap, c.current_hp + amount)
  await updateHp(c, newHp)
  hpAmounts.value[c.id] = 0
}

async function damage(c: PartyCharacter) {
  const amount = hpAmounts.value[c.id] || 0
  if (amount <= 0) return

  let remaining = amount
  let newTemp = c.temp_hp
  let newHp = c.current_hp

  if (newTemp > 0) {
    const absorbed = Math.min(newTemp, remaining)
    newTemp -= absorbed
    remaining -= absorbed
  }

  newHp = Math.max(0, newHp - remaining)
  await updateHp(c, newHp, undefined, newTemp)
  hpAmounts.value[c.id] = 0
}

async function fullHeal(c: PartyCharacter) {
  if (c.max_hp <= 0) return
  await updateHp(c, c.max_hp, undefined, 0)
  showToast(`${c.character_name || 'Character'} fully healed`, 'success')
}

// ---- Max HP ----

function startEditMax(c: PartyCharacter) {
  maxHpEditing.value = c.id
  maxHpInput.value = c.max_hp || 0
  tempHpEditing.value = null
}

async function saveMaxHp(c: PartyCharacter) {
  if (maxHpInput.value < 1) {
    showToast('Max HP must be at least 1', 'error')
    return
  }
  const newCurrent = c.max_hp <= 0 ? maxHpInput.value : Math.min(c.current_hp, maxHpInput.value)
  await updateHp(c, newCurrent, maxHpInput.value)
  maxHpEditing.value = null
  showToast(`Max HP set to ${maxHpInput.value}`, 'success')
}

// ---- Temp HP (common TTRPG rule: doesn't stack, take higher) ----

function startEditTemp(c: PartyCharacter) {
  tempHpEditing.value = c.id
  tempHpInput.value = 0
  maxHpEditing.value = null
}

async function saveTempHp(c: PartyCharacter) {
  if (tempHpInput.value < 0) return
  const newTemp = Math.max(c.temp_hp, tempHpInput.value)
  await updateHp(c, c.current_hp, undefined, newTemp)
  tempHpEditing.value = null
  if (newTemp === c.temp_hp && tempHpInput.value > 0) {
    showToast('Existing temp HP was higher — kept it', 'info')
  }
}

async function clearTempHp(c: PartyCharacter) {
  await updateHp(c, c.current_hp, undefined, 0)
}

// ---- Add / remove manual characters ----

async function addCharacter() {
  if (!campaignId.value) return
  const name = addName.value.trim()
  if (!name) {
    showToast('Enter a character name', 'error')
    return
  }
  const hp = addMaxHp.value ?? 0
  if (hp < 1) {
    showToast('Max HP must be at least 1', 'error')
    return
  }

  adding.value = true
  try {
    const { error } = await supabase.rpc('create_healer_character', {
      p_campaign_id: campaignId.value,
      p_character_name: name,
      p_max_hp: hp,
    })
    if (error) throw error
    addName.value = ''
    addMaxHp.value = null
    showToast(`${name} added to the party`, 'success')
    await fetchParty()
  } catch (e) {
    console.warn('Failed to add character', e)
    showToast('Failed to add character', 'error')
  } finally {
    adding.value = false
  }
}

async function removeCharacter(c: PartyCharacter) {
  try {
    const { error } = await supabase.rpc('delete_healer_character', {
      p_character_id: c.id,
    })
    if (error) throw error
    characters.value = characters.value.filter((x) => x.id !== c.id)
    showToast(`${c.character_name || 'Character'} removed`, 'info')
  } catch (e) {
    console.warn('Failed to remove character', e)
    showToast('Failed to remove character', 'error')
  }
}

function cancelInlineEdit() {
  maxHpEditing.value = null
  tempHpEditing.value = null
}

const isOwn = (c: PartyCharacter) => c.user_id === auth.user?.id
</script>

<template>
  <main class="healer-page">
    <header class="page-header">
      <h1 class="page-title">Healer's Kit</h1>
      <p class="page-sub">Campaign: {{ campaignName }}</p>
    </header>

    <!-- Quick-add form -->
    <section class="add-section">
      <h2 class="section-label">Add a character</h2>
      <form class="add-form" @submit.prevent="addCharacter">
        <input
          v-model="addName"
          type="text"
          class="add-input add-input--name"
          placeholder="Character name"
        />
        <input
          v-model.number="addMaxHp"
          type="number"
          min="1"
          class="add-input add-input--hp"
          placeholder="Max HP"
        />
        <button type="submit" class="btn btn-add" :disabled="adding">
          {{ adding ? 'Adding...' : 'Add to party' }}
        </button>
      </form>
    </section>

    <div v-if="loading" class="empty">Loading party...</div>

    <div v-else-if="characters.length === 0" class="empty">
      <p>No active characters in this campaign yet.</p>
      <p class="empty-hint">
        Add characters above, or have party members create one on the Characters page.
      </p>
    </div>

    <ul v-else class="party-grid">
      <li
        v-for="c in characters"
        :key="c.id"
        class="char-card"
        :class="cardClass(c)"
      >
        <!-- Identity row -->
        <div class="char-identity">
          <div v-if="c.avatar_url" class="char-avatar">
            <img :src="c.avatar_url" alt="" class="char-avatar-img" />
          </div>
          <div v-else class="char-avatar char-avatar--empty">&#x2694;&#xFE0F;</div>
          <div class="char-meta">
            <span class="char-name">{{ c.character_name || 'Unnamed' }}</span>
            <span class="status-badge" :class="statusClass(c)">{{ statusLabel(c) }}</span>
          </div>
          <div class="badge-stack">
            <span v-if="isOwn(c) && !c.is_npc" class="own-badge">You</span>
            <span v-if="c.is_npc" class="npc-badge">Manual</span>
          </div>
        </div>

        <!-- HP bar -->
        <div class="hp-section">
          <div class="hp-bar-track">
            <div
              class="hp-bar-fill"
              :class="hpBarClass(c)"
              :style="{ width: (c.max_hp > 0 ? hpPercent(c) : 100) + '%' }"
            >
              <div class="hp-bar-gloss" />
            </div>
          </div>
          <div class="hp-numbers">
            <div class="hp-text">
              <template v-if="c.max_hp > 0">
                <span class="hp-current">{{ c.current_hp }}</span>
                <span class="hp-sep">/</span>
                <span class="hp-max">{{ c.max_hp }}</span>
                <span class="hp-label">HP</span>
              </template>
              <span v-else class="hp-unset">HP not configured</span>
            </div>
            <div
              v-if="c.temp_hp > 0"
              class="temp-badge"
              title="Click to remove temp HP"
              @click="clearTempHp(c)"
            >
              <span class="temp-shield">&#x1F6E1;&#xFE0F;</span>
              <span class="temp-value">+{{ c.temp_hp }}</span>
              <span class="temp-label">temp</span>
            </div>
          </div>
        </div>

        <!-- Inline editors -->
        <div v-if="maxHpEditing === c.id" class="inline-editor">
          <label :for="'max-hp-' + c.id" class="field-label">Max HP</label>
          <div class="inline-row">
            <input
              :id="'max-hp-' + c.id"
              v-model.number="maxHpInput"
              type="number"
              min="1"
              class="hp-input hp-input--inline"
              @keydown.enter.prevent="saveMaxHp(c)"
              @keydown.escape.prevent="cancelInlineEdit"
            />
            <button class="btn btn-sm btn-save" @click="saveMaxHp(c)">Save</button>
            <button class="btn btn-sm btn-cancel" @click="cancelInlineEdit">Cancel</button>
          </div>
        </div>

        <div v-if="tempHpEditing === c.id" class="inline-editor">
          <label :for="'temp-hp-' + c.id" class="field-label">Grant temp HP (takes higher)</label>
          <div class="inline-row">
            <input
              :id="'temp-hp-' + c.id"
              v-model.number="tempHpInput"
              type="number"
              min="0"
              class="hp-input hp-input--inline"
              @keydown.enter.prevent="saveTempHp(c)"
              @keydown.escape.prevent="cancelInlineEdit"
            />
            <button class="btn btn-sm btn-save" @click="saveTempHp(c)">Grant</button>
            <button class="btn btn-sm btn-cancel" @click="cancelInlineEdit">Cancel</button>
          </div>
        </div>

        <!-- Controls -->
        <div class="controls">
          <div class="amount-row">
            <label :for="'hp-amt-' + c.id" class="visually-hidden">Amount</label>
            <input
              :id="'hp-amt-' + c.id"
              v-model.number="hpAmounts[c.id]"
              type="number"
              min="0"
              class="hp-input"
              placeholder="0"
              @keydown.enter.prevent="heal(c)"
            />
            <button class="btn btn-heal" :disabled="!hpAmounts[c.id]" @click="heal(c)">
              Heal
            </button>
            <button class="btn btn-damage" :disabled="!hpAmounts[c.id]" @click="damage(c)">
              Damage
            </button>
          </div>
          <div class="quick-actions">
            <button
              v-if="c.max_hp > 0"
              class="btn btn-sm btn-full-heal"
              :disabled="c.current_hp >= c.max_hp && c.temp_hp === 0"
              @click="fullHeal(c)"
            >
              Full heal
            </button>
            <button class="btn btn-sm btn-set-temp" @click="startEditTemp(c)">
              Temp HP
            </button>
            <button class="btn btn-sm btn-set-max" @click="startEditMax(c)">
              {{ c.max_hp > 0 ? 'Edit max' : 'Set max HP' }}
            </button>
            <button v-if="c.is_npc" class="btn btn-sm btn-remove" @click="removeCharacter(c)">
              Remove
            </button>
          </div>
        </div>
      </li>
    </ul>

    <button v-if="!loading && characters.length > 0" class="btn btn-refresh" @click="fetchParty">
      Refresh party
    </button>
  </main>
</template>

<style scoped>
/* ============================================================
   Design tokens
   ============================================================ */
.healer-page {
  --hp-green: #3a9a4f;
  --hp-green-glow: rgba(58, 154, 79, 0.35);
  --hp-yellow: #c7982a;
  --hp-yellow-glow: rgba(199, 152, 42, 0.35);
  --hp-red: #b33a2a;
  --hp-red-glow: rgba(179, 58, 42, 0.4);
  --hp-dead: #6b2020;
  --hp-dead-glow: rgba(107, 32, 32, 0.35);
  --hp-temp: #3a7abf;

  --card-radius: 14px;
  --card-border: 1px solid rgba(0, 0, 0, 0.06);
  --card-shadow: 0 4px 18px rgba(0, 0, 0, 0.06);
  --card-shadow-hover: 0 12px 32px rgba(0, 0, 0, 0.10);
}

/* ============================================================
   Page layout — wider for the grid
   ============================================================ */
.healer-page {
  padding: 3rem 1.25rem 4rem;
  max-width: 1060px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 1.75rem;
}

/* ---- Header ---- */
.page-header { text-align: center; }
.page-title {
  font-family: 'Cinzel', serif;
  font-size: 1.85rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
  letter-spacing: 0.02em;
}
.page-sub {
  color: var(--dnd-muted);
  font-size: 0.9rem;
  margin: 0.3rem 0 0;
}

/* ============================================================
   Add character section
   ============================================================ */
.add-section {
  padding: 1.25rem 1.5rem;
  background: var(--dnd-paper);
  border-radius: var(--card-radius);
  border: var(--card-border);
  box-shadow: var(--card-shadow);
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
}
.section-label {
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--dnd-muted);
  margin: 0;
}
.add-form {
  display: flex;
  gap: 0.5rem;
  flex-wrap: wrap;
}
.add-input {
  padding: 0.5rem 0.75rem;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.12);
  background: var(--dnd-bg);
  color: var(--dnd-ink);
  font-size: 0.9rem;
  font-family: inherit;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.add-input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.15);
}
.add-input::placeholder { color: var(--dnd-muted); }
.add-input--name { flex: 1; min-width: 10rem; }
.add-input--hp { width: 6rem; text-align: center; }

.btn-add { background: var(--dnd-accent); color: var(--dnd-on-accent); }
.btn-add:hover:not(:disabled) { filter: brightness(1.1); }

/* ============================================================
   Empty / loading states
   ============================================================ */
.empty {
  text-align: center;
  color: var(--dnd-muted);
  padding: 2.5rem 1rem;
  font-size: 0.95rem;
}
.empty p { margin: 0 0 0.25rem; }
.empty-hint { font-size: 0.85rem; }

/* ============================================================
   Party grid
   ============================================================ */
.party-grid {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 340px), 1fr));
  gap: 1.25rem;
}

/* ============================================================
   Character card
   ============================================================ */
.char-card {
  padding: 1.25rem 1.35rem;
  background: var(--dnd-paper);
  border-radius: var(--card-radius);
  border: var(--card-border);
  box-shadow: var(--card-shadow);
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
  transition:
    transform 0.22s ease,
    box-shadow 0.22s ease,
    border-color 0.3s ease;
  position: relative;
  overflow: hidden;
}
.char-card::before {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.3s;
}
.char-card:hover {
  transform: translateY(-3px);
  box-shadow: var(--card-shadow-hover);
}

/* Health-state card accents */
.char-card--healthy {
  border-left: 3px solid var(--hp-green);
}
.char-card--bloodied {
  border-left: 3px solid var(--hp-yellow);
}
.char-card--critical {
  border-left: 3px solid var(--hp-red);
  animation: pulse-critical 2.5s ease-in-out infinite;
}
.char-card--down {
  border-left: 3px solid var(--hp-dead);
  animation: pulse-down 3s ease-in-out infinite;
}

@keyframes pulse-critical {
  0%, 100% {
    box-shadow: var(--card-shadow);
  }
  50% {
    box-shadow: 0 0 0 2px rgba(179, 58, 42, 0.18), 0 4px 24px rgba(179, 58, 42, 0.12);
  }
}
@keyframes pulse-down {
  0%, 100% {
    box-shadow: var(--card-shadow);
  }
  50% {
    box-shadow: 0 0 0 3px rgba(107, 32, 32, 0.2), 0 4px 24px rgba(107, 32, 32, 0.15);
  }
}

/* ---- Identity ---- */
.char-identity {
  display: flex;
  align-items: center;
  gap: 0.8rem;
}
.char-avatar {
  width: 46px;
  height: 46px;
  border-radius: 50%;
  overflow: hidden;
  flex-shrink: 0;
  border: 2px solid var(--dnd-accent);
  transition: border-color 0.2s;
}
.char-card--down .char-avatar { border-color: var(--hp-dead); }
.char-card--critical .char-avatar { border-color: var(--hp-red); }
.char-avatar--empty {
  background: rgba(0, 0, 0, 0.04);
  border: 2px dashed rgba(0, 0, 0, 0.1);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.1rem;
}
.char-avatar-img { width: 100%; height: 100%; object-fit: cover; }

.char-meta {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  flex: 1;
  min-width: 0;
}
.char-name {
  font-family: 'Cinzel', serif;
  font-weight: 700;
  font-size: 1rem;
  color: var(--dnd-ink);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.badge-stack {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  align-items: flex-end;
  flex-shrink: 0;
}
.own-badge, .npc-badge {
  font-size: 0.58rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 0.12rem 0.4rem;
  border-radius: 4px;
}
.own-badge { background: var(--dnd-accent-2); color: var(--dnd-on-accent); }
.npc-badge { background: rgba(0, 0, 0, 0.07); color: var(--dnd-muted); }

/* ---- Status badge ---- */
.status-badge {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 0.1rem 0.45rem;
  border-radius: 4px;
  align-self: flex-start;
  transition: background 0.3s, color 0.3s;
}
.status--healthy { background: rgba(58, 154, 79, 0.12); color: var(--hp-green); }
.status--bloodied { background: rgba(199, 152, 42, 0.14); color: var(--hp-yellow); }
.status--critical { background: rgba(179, 58, 42, 0.12); color: var(--hp-red); }
.status--dead { background: rgba(107, 32, 32, 0.15); color: var(--hp-dead); }
.status--unset { background: rgba(0, 0, 0, 0.05); color: var(--dnd-muted); }

/* ============================================================
   HP bar — taller, glossy, glowing
   ============================================================ */
.hp-section {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}
.hp-bar-track {
  width: 100%;
  height: 18px;
  border-radius: 9px;
  background: rgba(0, 0, 0, 0.08);
  overflow: hidden;
  box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.08);
}
.hp-bar-fill {
  height: 100%;
  border-radius: 9px;
  transition: width 0.45s cubic-bezier(0.4, 0, 0.2, 1), background-color 0.3s, box-shadow 0.3s;
  min-width: 2px;
  position: relative;
  overflow: hidden;
}

/* Glossy highlight overlay */
.hp-bar-gloss {
  position: absolute;
  inset: 0;
  border-radius: inherit;
  background: linear-gradient(
    to bottom,
    rgba(255, 255, 255, 0.28) 0%,
    rgba(255, 255, 255, 0.06) 45%,
    transparent 55%,
    rgba(0, 0, 0, 0.06) 100%
  );
  pointer-events: none;
}

.hp-bar-fill--healthy {
  background-color: var(--hp-green);
  box-shadow: 0 0 10px var(--hp-green-glow);
}
.hp-bar-fill--bloodied {
  background-color: var(--hp-yellow);
  box-shadow: 0 0 10px var(--hp-yellow-glow);
}
.hp-bar-fill--critical {
  background-color: var(--hp-red);
  box-shadow: 0 0 10px var(--hp-red-glow);
  animation: bar-glow-red 1.8s ease-in-out infinite;
}
.hp-bar-fill--dead {
  background-color: var(--hp-dead);
  width: 0 !important;
  box-shadow: none;
}
.hp-bar-fill--unset {
  background-color: rgba(0, 0, 0, 0.06);
  box-shadow: none;
}

@keyframes bar-glow-red {
  0%, 100% { box-shadow: 0 0 8px var(--hp-red-glow); }
  50% { box-shadow: 0 0 18px var(--hp-red-glow), 0 0 4px var(--hp-red-glow); }
}

/* HP text */
.hp-numbers {
  display: flex;
  align-items: center;
  gap: 0.65rem;
  flex-wrap: wrap;
}
.hp-text {
  display: flex;
  align-items: baseline;
  gap: 0.15rem;
  font-size: 0.85rem;
  color: var(--dnd-muted);
}
.hp-current {
  font-weight: 700;
  font-size: 1.25rem;
  color: var(--dnd-ink);
  font-family: 'Cinzel', serif;
  transition: color 0.3s;
}
.char-card--down .hp-current { color: var(--hp-dead); }
.char-card--critical .hp-current { color: var(--hp-red); }
.hp-sep { color: var(--dnd-muted); }
.hp-max { font-weight: 600; color: var(--dnd-ink); }
.hp-label {
  font-size: 0.68rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin-left: 0.2rem;
}
.hp-unset {
  font-style: italic;
  font-size: 0.85rem;
}

/* ---- Temp HP badge ---- */
.temp-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  padding: 0.18rem 0.6rem;
  border-radius: 6px;
  background: rgba(58, 122, 191, 0.12);
  cursor: pointer;
  transition: background 0.15s, transform 0.15s;
}
.temp-badge:hover {
  background: rgba(58, 122, 191, 0.22);
  transform: scale(1.04);
}
.temp-shield { font-size: 0.75rem; }
.temp-value {
  font-weight: 700;
  font-size: 0.88rem;
  color: var(--hp-temp);
}
.temp-label {
  font-size: 0.6rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--hp-temp);
  opacity: 0.75;
}

/* ============================================================
   Inline editors
   ============================================================ */
.inline-editor {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  padding: 0.7rem 0.85rem;
  background: rgba(0, 0, 0, 0.03);
  border-radius: 8px;
}
.field-label {
  font-size: 0.68rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--dnd-muted);
}
.inline-row {
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

/* ============================================================
   Controls
   ============================================================ */
.controls {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  margin-top: auto;
}
.amount-row {
  display: flex;
  align-items: center;
  gap: 0.4rem;
}
.hp-input {
  width: 4rem;
  padding: 0.4rem 0.5rem;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.12);
  background: var(--dnd-bg);
  color: var(--dnd-ink);
  font-size: 0.92rem;
  font-family: inherit;
  text-align: center;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.hp-input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.15);
}
.hp-input--inline { width: 5rem; }

.quick-actions {
  display: flex;
  gap: 0.35rem;
  flex-wrap: wrap;
}

/* ============================================================
   Buttons
   ============================================================ */
.btn {
  padding: 0.42rem 0.8rem;
  border-radius: 8px;
  border: none;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  font-size: 0.82rem;
  transition: filter 0.15s, opacity 0.15s, transform 0.12s;
}
.btn:disabled { opacity: 0.45; cursor: not-allowed; }
.btn:active:not(:disabled) { transform: scale(0.97); }

.btn-heal { background: var(--hp-green); color: #fff; flex: 1; }
.btn-heal:hover:not(:disabled) { filter: brightness(1.1); }

.btn-damage { background: var(--hp-red); color: #fff; flex: 1; }
.btn-damage:hover:not(:disabled) { filter: brightness(1.1); }

.btn-sm {
  padding: 0.28rem 0.55rem;
  font-size: 0.74rem;
  border-radius: 6px;
}

.btn-full-heal { background: rgba(58, 154, 79, 0.12); color: var(--hp-green); }
.btn-full-heal:hover:not(:disabled) { background: rgba(58, 154, 79, 0.2); }

.btn-set-temp { background: rgba(58, 122, 191, 0.1); color: var(--hp-temp); }
.btn-set-temp:hover { background: rgba(58, 122, 191, 0.18); }

.btn-set-max { background: rgba(0, 0, 0, 0.05); color: var(--dnd-muted); }
.btn-set-max:hover { background: rgba(0, 0, 0, 0.08); color: var(--dnd-ink); }

.btn-save { background: var(--dnd-accent); color: var(--dnd-on-accent); }
.btn-save:hover { filter: brightness(1.1); }

.btn-cancel {
  background: transparent;
  color: var(--dnd-muted);
  border: 1px solid rgba(0, 0, 0, 0.1);
}
.btn-cancel:hover { background: rgba(0, 0, 0, 0.04); }

.btn-remove { background: transparent; color: var(--dnd-muted); border: 1px solid rgba(0, 0, 0, 0.1); }
.btn-remove:hover { background: rgba(179, 58, 42, 0.1); color: #b33a2a; }

.btn-refresh {
  align-self: center;
  background: rgba(0, 0, 0, 0.05);
  color: var(--dnd-muted);
  padding: 0.5rem 1.5rem;
  font-size: 0.85rem;
  border-radius: 10px;
}
.btn-refresh:hover { background: rgba(0, 0, 0, 0.08); color: var(--dnd-ink); }

.visually-hidden {
  position: absolute;
  width: 1px; height: 1px;
  padding: 0; margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap; border: 0;
}

/* ============================================================
   Responsive
   ============================================================ */
@media (max-width: 500px) {
  .healer-page { padding: 2rem 0.75rem 3rem; gap: 1.25rem; }
  .add-form { flex-direction: column; }
  .add-input--name { min-width: 0; }
  .add-input--hp { width: 100%; }
  .amount-row { flex-wrap: wrap; }
  .hp-input { width: 100%; flex: 1; }
  .btn-heal, .btn-damage { flex: 1; }
  .party-grid { gap: 1rem; }
}
</style>
