<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'
import { showToast } from '@/composables/useToast'

interface Character {
  id: string
  user_id: string
  campaign_id: string
  character_name: string
  avatar_url: string
  backstory: string
  backstory_url: string
  is_active: boolean
  created_at: string
  updated_at: string
}

const auth = useAuthStore()
const campaignStore = useCampaignStore()

const characters = ref<Character[]>([])
const loading = ref(true)

const editing = ref(false)
const editId = ref<string | null>(null)
const charName = ref('')
const backstory = ref('')
const backstoryUrl = ref('')
const avatarFile = ref<File | null>(null)
const avatarPreview = ref<string | null>(null)
const avatarUrl = ref('')
const saving = ref(false)

const campaignId = computed(() => campaignStore.activeCampaignId)
const campaignName = computed(() => campaignStore.activeCampaign?.name ?? 'Campaign')

async function fetchCharacters() {
  if (!campaignId.value) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('characters')
      .select('*')
      .eq('user_id', auth.user!.id)
      .eq('campaign_id', campaignId.value)
      .order('created_at')
    if (error) throw error
    characters.value = data as Character[]
  } catch (e) {
    console.warn('Failed to fetch characters', e)
    showToast('Failed to load characters', 'error')
  } finally {
    loading.value = false
  }
}

onMounted(fetchCharacters)
watch(campaignId, fetchCharacters)

function startCreate() {
  editing.value = true
  editId.value = null
  charName.value = ''
  backstory.value = ''
  backstoryUrl.value = ''
  avatarUrl.value = ''
  avatarFile.value = null
  avatarPreview.value = null
}

function startEdit(c: Character) {
  editing.value = true
  editId.value = c.id
  charName.value = c.character_name
  backstory.value = c.backstory
  backstoryUrl.value = c.backstory_url
  avatarUrl.value = c.avatar_url
  avatarFile.value = null
  avatarPreview.value = null
}

function cancelEdit() {
  editing.value = false
  editId.value = null
  if (avatarPreview.value) URL.revokeObjectURL(avatarPreview.value)
  avatarPreview.value = null
  avatarFile.value = null
}

function onAvatarSelected(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  avatarFile.value = file
  avatarPreview.value = URL.createObjectURL(file)
}

async function uploadAvatar(characterId: string): Promise<string | null> {
  if (!avatarFile.value) return null
  const ext = avatarFile.value.name.split('.').pop()
  const path = `${auth.user!.id}/${characterId}.${ext}`
  const { error } = await supabase.storage
    .from('avatars')
    .upload(path, avatarFile.value, { upsert: true })
  if (error) {
    console.warn('Avatar upload failed:', error.message)
    showToast('Avatar upload failed — character saved without picture', 'error')
    return null
  }
  return supabase.storage.from('avatars').getPublicUrl(path).data.publicUrl
}

async function handleSave() {
  if (!campaignId.value) return
  saving.value = true
  try {
    if (editId.value) {
      let newAvatar = avatarUrl.value
      if (avatarFile.value) {
        const uploaded = await uploadAvatar(editId.value)
        if (uploaded) newAvatar = uploaded
      }
      const { error } = await supabase
        .from('characters')
        .update({
          character_name: charName.value.trim(),
          backstory: backstory.value,
          backstory_url: backstoryUrl.value.trim(),
          avatar_url: newAvatar,
          updated_at: new Date().toISOString(),
        })
        .eq('id', editId.value)
      if (error) throw error
      showToast('Character updated', 'success')
    } else {
      const isFirst = characters.value.length === 0
      const { data, error } = await supabase
        .from('characters')
        .insert({
          user_id: auth.user!.id,
          campaign_id: campaignId.value,
          character_name: charName.value.trim() || 'Unnamed Adventurer',
          backstory: backstory.value,
          backstory_url: backstoryUrl.value.trim(),
          is_active: isFirst,
        })
        .select()
        .single()
      if (error) throw error

      if (avatarFile.value) {
        const uploaded = await uploadAvatar(data.id)
        if (uploaded) {
          await supabase.from('characters').update({ avatar_url: uploaded }).eq('id', data.id)
        }
      }
      showToast('Character created!', 'success')
    }

    cancelEdit()
    await fetchCharacters()
  } catch (e) {
    console.warn('Failed to save character', e)
    showToast('Failed to save character', 'error')
  } finally {
    saving.value = false
  }
}

async function setActive(id: string) {
  if (!campaignId.value) return
  try {
    await supabase
      .from('characters')
      .update({ is_active: false })
      .eq('user_id', auth.user!.id)
      .eq('campaign_id', campaignId.value)

    await supabase.from('characters').update({ is_active: true }).eq('id', id)

    characters.value = characters.value.map((c) => ({
      ...c,
      is_active: c.id === id,
    }))
    showToast('Active character set', 'success')
  } catch {
    showToast('Failed to set active character', 'error')
  }
}

async function deleteCharacter(id: string) {
  try {
    const { error } = await supabase.from('characters').delete().eq('id', id)
    if (error) throw error
    characters.value = characters.value.filter((c) => c.id !== id)
    if (editId.value === id) cancelEdit()
    showToast('Character deleted', 'info')
  } catch {
    showToast('Failed to delete character', 'error')
  }
}

const displayAvatar = computed(() => avatarPreview.value || avatarUrl.value)
</script>

<template>
  <main class="chars-page">
    <header class="page-header">
      <h1 class="page-title">Characters</h1>
      <p class="page-sub">Campaign: {{ campaignName }}</p>
    </header>

    <!-- Create/Edit form -->
    <section v-if="editing" class="char-form-card">
      <h2 class="form-heading">{{ editId ? 'Edit Character' : 'New Character' }}</h2>

      <div class="avatar-edit">
        <div v-if="displayAvatar" class="avatar-wrap">
          <img :src="displayAvatar" alt="Avatar preview" class="avatar-img" />
        </div>
        <div v-else class="avatar-placeholder">⚔️</div>
        <label class="btn btn-sm">
          {{ displayAvatar ? 'Change picture' : 'Add picture' }}
          <input type="file" accept="image/*" class="file-input" @change="onAvatarSelected" />
        </label>
      </div>

      <div class="field">
        <label for="char-name" class="label">Character name</label>
        <input id="char-name" v-model="charName" class="input" placeholder="Korhal Dawnrender" />
      </div>

      <div class="field">
        <label for="backstory" class="label">Backstory</label>
        <textarea id="backstory" v-model="backstory" class="input input-ta" rows="5" placeholder="Born under the crimson moon..." />
      </div>

      <div class="field">
        <label for="backstory-url" class="label">Backstory link (optional)</label>
        <input id="backstory-url" v-model="backstoryUrl" class="input" placeholder="https://..." />
      </div>

      <div class="form-actions">
        <button class="btn btn-primary" :disabled="saving" @click="handleSave">
          {{ saving ? 'Saving...' : editId ? 'Save' : 'Create' }}
        </button>
        <button class="btn btn-outline" :disabled="saving" @click="cancelEdit">Cancel</button>
      </div>
    </section>

    <!-- Character list -->
    <section v-else class="chars-section">
      <button class="btn btn-primary add-btn" @click="startCreate">+ New character</button>

      <div v-if="loading" class="empty">Loading characters...</div>
      <div v-else-if="characters.length === 0" class="empty">
        <p>No characters in this campaign yet. Create your first one!</p>
      </div>
      <ul v-else class="chars-list">
        <li v-for="c in characters" :key="c.id" class="char-card" :class="{ 'char-card--active': c.is_active }">
          <div class="char-top">
            <div v-if="c.avatar_url" class="char-avatar">
              <img :src="c.avatar_url" alt="" class="char-avatar-img" />
            </div>
            <div v-else class="char-avatar char-avatar--empty">⚔️</div>
            <div class="char-info">
              <span class="char-name">{{ c.character_name || 'Unnamed' }}</span>
              <span v-if="c.is_active" class="active-badge">Active</span>
            </div>
          </div>

          <p v-if="c.backstory" class="char-backstory">{{ c.backstory.slice(0, 120) }}{{ c.backstory.length > 120 ? '...' : '' }}</p>

          <div v-if="c.backstory_url" class="char-link-row">
            <a :href="c.backstory_url" target="_blank" rel="noopener noreferrer" class="char-link">Full backstory →</a>
          </div>

          <div class="char-actions">
            <button v-if="!c.is_active" class="btn btn-sm" @click="setActive(c.id)">Set active</button>
            <button class="btn btn-sm btn-outline-sm" @click="startEdit(c)">Edit</button>
            <button class="btn btn-sm btn-danger-sm" @click="deleteCharacter(c.id)">Delete</button>
          </div>
        </li>
      </ul>
    </section>
  </main>
</template>

<style scoped>
.chars-page {
  padding: 3rem 1rem 4rem;
  max-width: 700px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.page-header { text-align: center; }
.page-title {
  font-family: 'Cinzel', serif;
  font-size: 1.75rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
}
.page-sub {
  color: var(--dnd-muted);
  font-size: 0.9rem;
  margin: 0.25rem 0 0;
}

.char-form-card {
  padding: 1.5rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0,0,0,0.06);
  box-shadow: 0 8px 30px rgba(0,0,0,0.08);
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
.form-heading {
  font-family: 'Cinzel', serif;
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
}

.avatar-edit { display: flex; align-items: center; gap: 1rem; }
.avatar-wrap {
  width: 72px; height: 72px;
  border-radius: 50%;
  overflow: hidden;
  border: 3px solid var(--dnd-accent);
  flex-shrink: 0;
}
.avatar-img { width: 100%; height: 100%; object-fit: cover; }
.avatar-placeholder {
  width: 72px; height: 72px;
  border-radius: 50%;
  background: rgba(0,0,0,0.04);
  border: 3px dashed rgba(0,0,0,0.1);
  display: flex; align-items: center; justify-content: center;
  font-size: 1.5rem; flex-shrink: 0;
}

.field { display: flex; flex-direction: column; gap: 0.2rem; }
.label {
  font-size: 0.78rem; font-weight: 600;
  text-transform: uppercase; letter-spacing: 0.04em;
  color: var(--dnd-muted);
}
.input {
  padding: 0.55rem 0.75rem;
  border-radius: 8px;
  border: 1px solid rgba(0,0,0,0.12);
  background: var(--dnd-bg);
  color: var(--dnd-ink);
  font-size: 0.95rem;
  font-family: inherit;
}
.input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139,58,47,0.15);
}
.input::placeholder { color: var(--dnd-muted); }
.input-ta { resize: vertical; min-height: 6rem; line-height: 1.6; }

.form-actions { display: flex; gap: 0.5rem; }

.file-input {
  position: absolute; width: 1px; height: 1px;
  opacity: 0; overflow: hidden; clip: rect(0,0,0,0);
}

.chars-section {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.add-btn { align-self: flex-start; }

.empty {
  text-align: center; color: var(--dnd-muted);
  padding: 2rem; font-size: 0.95rem;
}
.empty p { margin: 0; }

.chars-list {
  list-style: none; margin: 0; padding: 0;
  display: flex; flex-direction: column; gap: 1rem;
}

.char-card {
  padding: 1.25rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0,0,0,0.06);
  box-shadow: 0 4px 16px rgba(0,0,0,0.06);
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}
.char-card--active {
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 2px rgba(139,58,47,0.12), 0 4px 16px rgba(0,0,0,0.06);
}

.char-top { display: flex; align-items: center; gap: 1rem; }
.char-avatar {
  width: 56px; height: 56px; border-radius: 50%;
  overflow: hidden; flex-shrink: 0;
  border: 2px solid var(--dnd-accent);
}
.char-avatar--empty {
  background: rgba(0,0,0,0.04);
  border: 2px dashed rgba(0,0,0,0.1);
  display: flex; align-items: center; justify-content: center;
  font-size: 1.25rem;
}
.char-avatar-img { width: 100%; height: 100%; object-fit: cover; }
.char-info { display: flex; flex-direction: column; gap: 0.15rem; }
.char-name {
  font-family: 'Cinzel', serif;
  font-weight: 700; font-size: 1.1rem;
  color: var(--dnd-ink);
}
.active-badge {
  font-size: 0.65rem; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.05em;
  background: var(--dnd-accent); color: var(--dnd-paper);
  padding: 0.1rem 0.4rem; border-radius: 4px;
  align-self: flex-start;
}

.char-backstory {
  font-size: 0.88rem; color: var(--dnd-ink);
  line-height: 1.5; margin: 0;
  white-space: pre-wrap;
}

.char-link-row { margin: 0; }
.char-link {
  color: var(--dnd-accent); font-weight: 600;
  font-size: 0.88rem; text-decoration: none;
}
.char-link:hover { text-decoration: underline; }

.char-actions { display: flex; gap: 0.4rem; flex-wrap: wrap; }

.btn {
  padding: 0.5rem 1rem; border-radius: 8px; border: none;
  font-weight: 600; font-family: inherit; cursor: pointer;
  font-size: 0.9rem; transition: filter 0.15s, opacity 0.15s;
}
.btn:disabled { opacity: 0.6; cursor: not-allowed; }
.btn-primary { background: var(--dnd-accent); color: var(--dnd-paper); }
.btn-primary:hover:not(:disabled) { filter: brightness(1.1); }
.btn-outline {
  background: transparent; color: var(--dnd-muted);
  border: 1px solid rgba(0,0,0,0.12);
}
.btn-outline:hover { background: rgba(0,0,0,0.04); color: var(--dnd-ink); }
.btn-sm {
  padding: 0.3rem 0.65rem; font-size: 0.8rem;
  border-radius: 6px; background: var(--dnd-accent-2);
  color: var(--dnd-paper); border: none;
  font-weight: 600; font-family: inherit; cursor: pointer;
}
.btn-sm:hover { filter: brightness(1.08); }
.btn-outline-sm {
  background: transparent; color: var(--dnd-muted);
  border: 1px solid rgba(0,0,0,0.1);
}
.btn-outline-sm:hover { background: rgba(0,0,0,0.04); color: var(--dnd-ink); }
.btn-danger-sm {
  background: transparent; color: var(--dnd-muted);
  border: 1px solid rgba(0,0,0,0.1);
}
.btn-danger-sm:hover { background: rgba(179,58,42,0.1); color: #b33a2a; }

@media (max-width: 500px) {
  .avatar-edit { flex-direction: column; }
}
</style>
