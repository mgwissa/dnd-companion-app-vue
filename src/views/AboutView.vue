<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { showToast } from '@/composables/useToast'

const auth = useAuthStore()

const characterName = ref('')
const avatarUrl = ref('')
const backstory = ref('')
const backstoryUrl = ref('')

const loading = ref(true)
const saving = ref(false)
const editing = ref(false)
const avatarFile = ref<File | null>(null)
const avatarPreview = ref<string | null>(null)

async function fetchProfile() {
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', auth.user!.id)
      .maybeSingle()
    if (error) throw error

    if (data) {
      characterName.value = data.character_name ?? ''
      avatarUrl.value = data.avatar_url ?? ''
      backstory.value = data.backstory ?? ''
      backstoryUrl.value = data.backstory_url ?? ''
    }
  } catch (e) {
    console.warn('Failed to load profile', e)
    showToast('Failed to load profile', 'error')
  } finally {
    loading.value = false
  }
}

function onAvatarSelected(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  avatarFile.value = file
  avatarPreview.value = URL.createObjectURL(file)
}

async function uploadAvatar(): Promise<string | null> {
  if (!avatarFile.value) return null

  const ext = avatarFile.value.name.split('.').pop()
  const path = `${auth.user!.id}/avatar.${ext}`

  const { error } = await supabase.storage
    .from('avatars')
    .upload(path, avatarFile.value, { upsert: true })
  if (error) throw error

  const { data } = supabase.storage.from('avatars').getPublicUrl(path)
  return data.publicUrl
}

async function saveProfile() {
  saving.value = true
  try {
    let newAvatarUrl = avatarUrl.value
    if (avatarFile.value) {
      const uploaded = await uploadAvatar()
      if (uploaded) newAvatarUrl = uploaded
    }

    const payload = {
      id: auth.user!.id,
      character_name: characterName.value.trim(),
      avatar_url: newAvatarUrl,
      backstory: backstory.value,
      backstory_url: backstoryUrl.value.trim(),
      updated_at: new Date().toISOString(),
    }

    const { error } = await supabase
      .from('profiles')
      .upsert(payload)
    if (error) throw error

    avatarUrl.value = newAvatarUrl
    avatarFile.value = null
    avatarPreview.value = null
    editing.value = false
    showToast('Profile saved', 'success')
  } catch (e) {
    console.warn('Failed to save profile', e)
    showToast('Failed to save profile', 'error')
  } finally {
    saving.value = false
  }
}

function cancelEdit() {
  editing.value = false
  avatarFile.value = null
  if (avatarPreview.value) {
    URL.revokeObjectURL(avatarPreview.value)
    avatarPreview.value = null
  }
  fetchProfile()
}

const displayAvatar = () => avatarPreview.value || avatarUrl.value

onMounted(fetchProfile)
</script>

<template>
  <main class="profile-page">
    <div v-if="loading" class="profile-loading">Loading profile...</div>

    <template v-else>
      <!-- View mode -->
      <div v-if="!editing" class="profile-card">
        <div class="profile-header">
          <div v-if="avatarUrl" class="avatar-wrap">
            <img :src="avatarUrl" alt="Character avatar" class="avatar-img" />
          </div>
          <div v-else class="avatar-placeholder">
            <span class="avatar-placeholder-icon">⚔️</span>
          </div>

          <div class="profile-info">
            <h1 class="character-name">
              {{ characterName || 'Unnamed Adventurer' }}
            </h1>
            <p class="profile-email">{{ auth.user?.email }}</p>
          </div>
        </div>

        <section v-if="backstory" class="backstory-section">
          <h2 class="section-heading">Backstory</h2>
          <p class="backstory-text">{{ backstory }}</p>
        </section>

        <section v-if="backstoryUrl" class="backstory-link-section">
          <a
            :href="backstoryUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="backstory-link"
          >
            View full backstory →
          </a>
        </section>

        <div v-if="!backstory && !backstoryUrl && !characterName" class="empty-profile">
          <p>You haven't set up your character profile yet.</p>
        </div>

        <button type="button" class="btn btn-primary" @click="editing = true">
          Edit Profile
        </button>
      </div>

      <!-- Edit mode -->
      <form v-else class="profile-card" @submit.prevent="saveProfile">
        <h1 class="page-heading">Edit Profile</h1>

        <div class="avatar-edit">
          <div v-if="displayAvatar()" class="avatar-wrap">
            <img :src="displayAvatar()!" alt="Avatar preview" class="avatar-img" />
          </div>
          <div v-else class="avatar-placeholder">
            <span class="avatar-placeholder-icon">⚔️</span>
          </div>
          <label class="btn btn-secondary btn-file">
            {{ avatarUrl || avatarPreview ? 'Change picture' : 'Add picture' }}
            <input
              type="file"
              accept="image/*"
              class="file-input"
              @change="onAvatarSelected"
            />
          </label>
        </div>

        <div class="field">
          <label for="char-name" class="label">Character name</label>
          <input
            id="char-name"
            v-model="characterName"
            type="text"
            class="input"
            placeholder="Korhal Dawnrender"
          />
        </div>

        <div class="field">
          <label for="backstory" class="label">Backstory</label>
          <textarea
            id="backstory"
            v-model="backstory"
            class="input input-textarea"
            rows="6"
            placeholder="Born under the crimson moon..."
          />
        </div>

        <div class="field">
          <label for="backstory-url" class="label">Backstory link (optional)</label>
          <input
            id="backstory-url"
            v-model="backstoryUrl"
            type="url"
            class="input"
            placeholder="https://docs.google.com/..."
          />
        </div>

        <div class="form-actions">
          <button type="submit" class="btn btn-primary" :disabled="saving">
            {{ saving ? 'Saving...' : 'Save' }}
          </button>
          <button type="button" class="btn btn-secondary" :disabled="saving" @click="cancelEdit">
            Cancel
          </button>
        </div>
      </form>
    </template>
  </main>
</template>

<style scoped>
.profile-page {
  padding: 3rem 1rem 4rem;
  max-width: 540px;
  margin: 0 auto;
  min-height: 60vh;
}

.profile-loading {
  text-align: center;
  color: var(--dnd-muted);
  padding: 4rem 0;
  font-size: 0.95rem;
}

.profile-card {
  padding: 2rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.08);
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.profile-header {
  display: flex;
  align-items: center;
  gap: 1.5rem;
}

.avatar-wrap {
  flex-shrink: 0;
  width: 100px;
  height: 100px;
  border-radius: 50%;
  overflow: hidden;
  border: 3px solid var(--dnd-accent);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
}

.avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.avatar-placeholder {
  flex-shrink: 0;
  width: 100px;
  height: 100px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.05);
  border: 3px dashed rgba(0, 0, 0, 0.12);
  display: flex;
  align-items: center;
  justify-content: center;
}

.avatar-placeholder-icon {
  font-size: 2rem;
}

.avatar-edit {
  display: flex;
  align-items: center;
  gap: 1.25rem;
}

.profile-info {
  min-width: 0;
}

.character-name {
  font-family: 'Cinzel', serif;
  font-size: clamp(1.5rem, 4vw, 2rem);
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0 0 0.25rem;
  line-height: 1.2;
}

.profile-email {
  font-size: 0.85rem;
  color: var(--dnd-muted);
  margin: 0;
}

.page-heading {
  font-family: 'Cinzel', serif;
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
}

.section-heading {
  font-family: 'Cinzel', serif;
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0 0 0.5rem;
}

.backstory-section {
  padding-top: 0.5rem;
  border-top: 1px solid rgba(0, 0, 0, 0.06);
}

.backstory-text {
  color: var(--dnd-ink);
  font-size: 0.95rem;
  line-height: 1.7;
  margin: 0;
  white-space: pre-wrap;
}

.backstory-link-section {
  padding-top: 0.25rem;
}

.backstory-link {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  color: var(--dnd-accent);
  font-weight: 600;
  font-size: 0.95rem;
  text-decoration: none;
  transition: filter 0.15s;
}
.backstory-link:hover {
  filter: brightness(1.15);
  text-decoration: underline;
  text-underline-offset: 2px;
}

.empty-profile {
  text-align: center;
  color: var(--dnd-muted);
  font-size: 0.95rem;
  padding: 1rem 0;
}
.empty-profile p {
  margin: 0;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.label {
  font-size: 0.8125rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--dnd-muted);
}

.input {
  padding: 0.6rem 0.75rem;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.12);
  background: var(--dnd-bg);
  color: var(--dnd-ink);
  font-size: 1rem;
  font-family: inherit;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.input::placeholder {
  color: var(--dnd-muted);
}
.input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.15);
}

.input-textarea {
  resize: vertical;
  min-height: 8rem;
  line-height: 1.6;
}

.form-actions {
  display: flex;
  gap: 0.75rem;
}

.btn {
  padding: 0.6rem 1.25rem;
  border-radius: 8px;
  border: none;
  font-size: 0.95rem;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  transition: filter 0.15s, opacity 0.15s;
}
.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.btn-primary {
  background: var(--dnd-accent);
  color: var(--dnd-paper);
}
.btn-primary:hover:not(:disabled) {
  filter: brightness(1.1);
}
.btn-secondary {
  background: var(--dnd-accent-2);
  color: var(--dnd-paper);
}
.btn-secondary:hover:not(:disabled) {
  filter: brightness(1.08);
}
.btn-file {
  cursor: pointer;
}

.file-input {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
}

@media (max-width: 480px) {
  .profile-header {
    flex-direction: column;
    text-align: center;
  }
  .avatar-edit {
    flex-direction: column;
  }
}
</style>
