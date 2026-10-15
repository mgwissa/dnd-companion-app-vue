<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import { showToast, clearToastTimer } from '@/composables/useToast'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'
import SessionImport from '@/components/SessionImport.vue'
import MarkdownContent from '@/components/MarkdownContent.vue'
import { isPlayedOn, localPlayedOn } from '@/lib/sessionImport'

type Note = {
  id: string
  title: string
  body: string
  updatedAt: number
  tags: string[]
  isShared: boolean
  userId: string
  noteType: 'note' | 'session' | 'transcript'
  playedOn: string | null
  resumePoint: string
  parentSessionId: string | null
  recapShareToken: string | null
}

interface DbNote {
  id: string
  user_id: string
  campaign_id: string | null
  title: string
  body: string
  tags: string[]
  is_shared: boolean
  updated_at: string
  created_at: string
  note_type: 'note' | 'session' | 'transcript'
  played_on: string | null
  resume_point: string
  parent_session_id: string | null
  recap_share_token: string | null
}

type CampaignThread = {
  id: string
  title: string
  is_done: boolean
  created_by: string
}

function dbToNote(row: DbNote): Note {
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    tags: row.tags ?? [],
    isShared: row.is_shared,
    userId: row.user_id,
    noteType: row.note_type,
    playedOn: row.played_on,
    resumePoint: row.resume_point ?? '',
    parentSessionId: row.parent_session_id,
    recapShareToken: row.recap_share_token,
    updatedAt: new Date(row.updated_at).getTime(),
  }
}

const auth = useAuthStore()
const campaignStore = useCampaignStore()
const route = useRoute()

const notes = ref<Note[]>([])
const activeId = ref<string | null>(null)
const isEditing = ref(false)
const loading = ref(false)

const title = ref('')
const body = ref('')
const editorTags = ref<string[]>([])
const editorShared = ref(false)
const editorPlayedOn = ref('')
const editorResumePoint = ref('')
const shareBusy = ref(false)
const recapLink = computed(() => activeNote.value?.recapShareToken ? new URL(`?recap=${activeNote.value.recapShareToken}`, `${window.location.origin}${import.meta.env.BASE_URL}`).href : '')

const searchQuery = ref('')
const selectedTagFilters = ref<string[]>([])
const newTagInput = ref('')

const newTitle = ref('')
const newBody = ref('')
const newShared = ref(false)
const threads = ref<CampaignThread[]>([])
const newThreadTitle = ref('')
const threadsLoading = ref(false)
const sessionMode = ref(false)
const quickCaptureType = ref('Discovery')
const quickCaptureText = ref('')

const isMyNote = (n: Note) => n.userId === auth.user?.id

async function fetchNotes() {
  if (!campaignStore.activeCampaignId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('notes')
      .select('*')
      .eq('campaign_id', campaignStore.activeCampaignId)
      .order('updated_at', { ascending: false })
    if (error) throw error
    notes.value = (data as DbNote[]).map(dbToNote)
  } catch (e) {
    console.warn('Failed to fetch notes', e)
    showToast('Failed to load notes', 'error')
  } finally {
    loading.value = false
  }
}

async function fetchThreads() {
  if (!campaignStore.activeCampaignId) return
  threadsLoading.value = true
  try {
    const { data, error } = await supabase
      .from('campaign_threads')
      .select('id, title, is_done, created_by')
      .eq('campaign_id', campaignStore.activeCampaignId)
      .order('is_done', { ascending: true })
      .order('created_at', { ascending: false })
    if (error) throw error
    threads.value = (data ?? []) as CampaignThread[]
  } catch (error) {
    console.warn('Failed to load campaign threads', error)
  } finally {
    threadsLoading.value = false
  }
}

async function addThread() {
  const titleValue = newThreadTitle.value.trim()
  if (!titleValue || !campaignStore.activeCampaignId || !auth.user) return
  const { data, error } = await supabase
    .from('campaign_threads')
    .insert({
      campaign_id: campaignStore.activeCampaignId,
      created_by: auth.user.id,
      title: titleValue,
    })
    .select('id, title, is_done, created_by')
    .single()
  if (error) {
    showToast('Failed to add thread. Apply the latest database migration first.', 'error')
    return
  }
  threads.value.unshift(data as CampaignThread)
  newThreadTitle.value = ''
}

async function toggleThread(thread: CampaignThread) {
  const { error } = await supabase
    .from('campaign_threads')
    .update({ is_done: !thread.is_done, updated_at: new Date().toISOString() })
    .eq('id', thread.id)
  if (error) {
    showToast('Failed to update thread', 'error')
    return
  }
  thread.is_done = !thread.is_done
  threads.value.sort((a, b) => Number(a.is_done) - Number(b.is_done))
}

async function deleteThread(thread: CampaignThread) {
  const { error } = await supabase.from('campaign_threads').delete().eq('id', thread.id)
  if (error) {
    showToast('Failed to remove thread', 'error')
    return
  }
  threads.value = threads.value.filter((item) => item.id !== thread.id)
}

watch(() => campaignStore.activeCampaignId, () => {
  activeId.value = null
  fetchNotes()
  fetchThreads()
})

async function onSessionImported(noteId: string) {
  await fetchNotes()
  await fetchThreads()
  selectNote(noteId)
  showToast('Session imported', 'success')
}

async function createNote(asSession = false) {
  if (!campaignStore.activeCampaignId) return
  const noteTitle = newTitle.value.trim() || `Untitled ${notes.value.length + 1}`
  const noteBody = newBody.value

  try {
    const { data, error } = await supabase
      .from('notes')
      .insert({
        user_id: auth.user!.id,
        campaign_id: campaignStore.activeCampaignId,
        title: noteTitle,
        body: noteBody,
        tags: asSession ? ['session'] : [],
        note_type: asSession ? 'session' : 'note',
        played_on: asSession ? localPlayedOn() : null,
        is_shared: newShared.value,
        updated_at: new Date().toISOString(),
      })
      .select()
      .single()
    if (error) throw error

    const n = dbToNote(data as DbNote)
    notes.value.unshift(n)
    selectNote(n.id)
    isEditing.value = true
    newTitle.value = ''
    newBody.value = ''
    newShared.value = false
    showToast('Created', 'success')
  } catch (e) {
    console.warn('Failed to create note', e)
    showToast('Failed to create note', 'error')
  }
}

async function startSession() {
  sessionMode.value = true
  const dateLabel = new Intl.DateTimeFormat(undefined, {
    month: 'numeric',
    day: 'numeric',
    year: 'numeric',
  }).format(new Date())
  newTitle.value = `${dateLabel} Session`
  newBody.value = `## Recap\n\n## Discoveries\n\n## NPCs & locations\n\n## Open threads\n\n`
  newShared.value = true
  await createNote(true)
}

async function addQuickCapture() {
  const capture = quickCaptureText.value.trim()
  if (!capture || !activeId.value) return
  body.value = `${body.value.trimEnd()}\n\n## ${quickCaptureType.value}\n${capture}\n`
  quickCaptureText.value = ''
  await saveActive()
}

function selectNote(id: string) {
  const n = notes.value.find((x) => x.id === id)
  if (!n) return
  activeId.value = id
  isEditing.value = false
  title.value = n.title
  body.value = n.body
  editorTags.value = [...n.tags]
  editorShared.value = n.isShared
  editorPlayedOn.value = n.playedOn ?? ''
  editorResumePoint.value = n.resumePoint
}

async function deleteNote(id: string) {
  const note = notes.value.find((item) => item.id === id)
  const noteTitle = note?.title.trim() || 'this note'
  if (!window.confirm(`Delete "${noteTitle}"? This cannot be undone.`)) return

  try {
    const { error } = await supabase.from('notes').delete().eq('id', id)
    if (error) throw error

    const i = notes.value.findIndex((x) => x.id === id)
    if (i !== -1) notes.value.splice(i, 1)
    if (activeId.value === id) {
      activeId.value = null
      title.value = ''
      body.value = ''
      editorTags.value = []
    }
    showToast('Deleted', 'error')
  } catch (e) {
    console.warn('Failed to delete note', e)
    showToast('Failed to delete note', 'error')
  }
}

function exportNotes() {
  const data = JSON.stringify(notes.value, null, 2)
  const blob = new Blob([data], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'ttrpg-notes.json'
  a.click()
  URL.revokeObjectURL(url)
  showToast('Exported notes', 'info')
}

async function importNotes(file: File | null) {
  if (!file) return
  const text = await file.text()
  try {
    const parsed = JSON.parse(text) as Partial<Note>[]
    if (!Array.isArray(parsed) || parsed.length === 0) {
      showToast('No notes found in file', 'error')
      return
    }

    const rows = parsed
      .filter((n) => n.title || n.body)
      .map((n) => ({
        user_id: auth.user!.id,
        campaign_id: campaignStore.activeCampaignId,
        title: n.title ?? '',
        body: n.body ?? '',
        tags: Array.isArray(n.tags) ? n.tags : [],
        is_shared: false,
        note_type: ['session', 'transcript'].includes(n.noteType ?? '') ? n.noteType : 'note',
        played_on: isPlayedOn(n.playedOn) ? n.playedOn : null,
        resume_point: typeof n.resumePoint === 'string' ? n.resumePoint : '',
        updated_at: n.updatedAt ? new Date(n.updatedAt).toISOString() : new Date().toISOString(),
      }))

    const { data, error } = await supabase.from('notes').insert(rows).select()
    if (error) throw error

    const imported = (data as DbNote[]).map(dbToNote)
    notes.value = [...imported, ...notes.value].sort((a, b) => b.updatedAt - a.updatedAt)

    if (activeId.value) {
      const cur = notes.value.find((n) => n.id === activeId.value)
      if (cur) {
        title.value = cur.title
        body.value = cur.body
        editorTags.value = [...cur.tags]
        editorShared.value = cur.isShared
        editorPlayedOn.value = cur.playedOn ?? ''
        editorResumePoint.value = cur.resumePoint
      }
    }
    showToast(`Imported ${imported.length} notes`, 'info')
  } catch (e) {
    console.warn('Failed to import notes', e)
    showToast('Failed to import notes', 'error')
  }
}

function onFileChange(e: Event) {
  const input = e.target as HTMLInputElement | null
  const file = input?.files?.[0] ?? null
  importNotes(file)
}

async function saveActive() {
  if (!activeId.value) return
  const i = notes.value.findIndex((x) => x.id === activeId.value)
  if (i === -1) return

  if (editorPlayedOn.value && !isPlayedOn(editorPlayedOn.value)) {
    showToast('Enter a valid played date', 'error')
    return
  }
  const now = new Date()
  try {
    const { error } = await supabase
      .from('notes')
      .update({
        title: title.value,
        body: body.value,
        tags: [...editorTags.value],
        is_shared: notes.value[i]!.noteType === 'transcript' ? false : editorShared.value,
        played_on: editorPlayedOn.value || null,
        resume_point: editorResumePoint.value,
        updated_at: now.toISOString(),
      })
      .eq('id', activeId.value)
    if (error) throw error

    notes.value[i] = {
      ...notes.value[i],
      title: title.value,
      body: body.value,
      tags: [...editorTags.value],
      isShared: notes.value[i]!.noteType === 'transcript' ? false : editorShared.value,
      playedOn: editorPlayedOn.value || null,
      resumePoint: editorResumePoint.value,
      updatedAt: now.getTime(),
    }
    showToast('Saved', 'success')
  } catch (e) {
    console.warn('Failed to save note', e)
    showToast('Failed to save note', 'error')
  }
}

async function setRecapLink(enabled: boolean) {
  const note = activeNote.value
  if (!note || !isMyNote(note) || note.noteType !== 'session' || shareBusy.value) return
  if (enabled && unsaved.value) {
    showToast('Save your reviewed changes before creating a recap link', 'info')
    return
  }
  shareBusy.value = true
  try {
    const token = enabled ? crypto.randomUUID() : null
    const { error } = await supabase.from('notes').update({ recap_share_token: token }).eq('id', note.id)
    if (error) throw error
    note.recapShareToken = token
    showToast(enabled ? 'Recap link ready to share' : 'Recap link revoked', 'success')
  } catch {
    showToast('Could not update recap link', 'error')
  } finally {
    shareBusy.value = false
  }
}

async function copyRecapLink() {
  try {
    await navigator.clipboard.writeText(recapLink.value)
    showToast('Recap link copied', 'success')
  } catch {
    showToast('Select and copy the link below', 'info')
  }
}

async function deleteActive() {
  if (activeId.value) await deleteNote(activeId.value)
}

function toggleTagFilter(tag: string) {
  const i = selectedTagFilters.value.indexOf(tag)
  if (i === -1) selectedTagFilters.value = [...selectedTagFilters.value, tag]
  else selectedTagFilters.value = selectedTagFilters.value.filter((_, j) => j !== i)
}

function clearFilters() {
  searchQuery.value = ''
  selectedTagFilters.value = []
}

function addTag(tag: string) {
  const t = tag.trim()
  if (!t || editorTags.value.includes(t)) return
  editorTags.value = [...editorTags.value, t]
}

function addTagFromInput() {
  addTag(newTagInput.value)
  newTagInput.value = ''
}

function removeTag(index: number) {
  editorTags.value = editorTags.value.filter((_, i) => i !== index)
}

function formatDate(ms: number): string {
  return new Date(ms).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: new Date(ms).getFullYear() !== new Date().getFullYear() ? 'numeric' : undefined,
    hour: '2-digit',
    minute: '2-digit',
  })
}

function handleSaveKey(e: KeyboardEvent) {
  if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.code === 'KeyS')) {
    e.preventDefault()
    saveActive()
  }
}

onMounted(async () => {
  window.addEventListener('keydown', handleSaveKey)
  await fetchNotes()
  await fetchThreads()
  const requestedNote = typeof route.query.note === 'string' ? route.query.note : null
  if (requestedNote && notes.value.some((note) => note.id === requestedNote)) {
    sessionMode.value = true
    selectNote(requestedNote)
  } else if (route.query.start === 'session') {
    await startSession()
  }

})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleSaveKey)
  clearToastTimer()
})

const sortedNotes = computed(() => notes.value.slice().sort((a, b) => b.updatedAt - a.updatedAt))

const allTags = computed(() => {
  const set = new Set<string>()
  notes.value.forEach((n) => n.tags.forEach((t) => set.add(t)))
  return [...set].sort((a, b) => a.localeCompare(b))
})

const filteredNotes = computed(() => {
  let list = sortedNotes.value
  const q = searchQuery.value.trim().toLowerCase()
  if (q) {
    list = list.filter(
      (n) =>
        n.title.toLowerCase().includes(q) || (n.body || '').toLowerCase().includes(q),
    )
  }
  const selected = selectedTagFilters.value
  if (selected.length > 0) {
    list = list.filter((n) => {
      const noteTags = n.tags.map((t) => t.toLowerCase())
      return selected.every((s) => noteTags.includes(s.toLowerCase()))
    })
  }
  return list
})

const hasActiveFilters = computed(
  () => searchQuery.value.trim() !== '' || selectedTagFilters.value.length > 0,
)

const activeNote = computed(() => notes.value.find((n) => n.id === activeId.value) ?? null)

function tagsEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false
  const sa = [...a].sort()
  const sb = [...b].sort()
  return sa.every((t, i) => t === sb[i])
}

const unsaved = computed(() => {
  if (!activeNote.value) return false
  if (activeNote.value.title !== title.value || activeNote.value.body !== body.value) return true
  if (activeNote.value.isShared !== editorShared.value) return true
  if ((activeNote.value.playedOn ?? '') !== editorPlayedOn.value || activeNote.value.resumePoint !== editorResumePoint.value) return true
  return !tagsEqual(activeNote.value.tags, editorTags.value)
})
</script>

<template>
  <main class="notes-page" role="main">
    <nav class="campaign-context" aria-label="Campaign workspace">
      <RouterLink to="/" class="context-home">{{ campaignStore.activeCampaign?.name ?? 'Campaign hub' }}</RouterLink>
      <span class="context-divider" aria-hidden="true">/</span>
      <span class="context-current">Notes</span>
      <div class="context-links">
        <RouterLink to="/" class="context-link">Hub</RouterLink>
        <RouterLink to="/characters" class="context-link">Characters</RouterLink>
        <RouterLink to="/healer" class="context-link">Health</RouterLink>
        <RouterLink to="/links" class="context-link">Links</RouterLink>
      </div>
    </nav>
    <section v-if="sessionMode && activeId" class="session-mode-bar" aria-label="Session mode">
      <div>
        <span class="page-kicker">Session mode</span>
        <strong>Capture the moment. Sort it out later.</strong>
      </div>
      <form class="quick-capture" @submit.prevent="addQuickCapture">
        <select v-model="quickCaptureType" aria-label="Capture type">
          <option>Discovery</option>
          <option>NPC</option>
          <option>Location</option>
          <option>Decision</option>
          <option>Open thread</option>
        </select>
        <input v-model="quickCaptureText" type="text" placeholder="Quick capture..." aria-label="Quick capture" />
        <button type="submit" class="btn btn--primary">Add</button>
      </form>
      <button type="button" class="session-mode-close" @click="sessionMode = false">Exit</button>
    </section>
    <header class="page-intro">
      <p class="page-kicker">Campaign memory / shared journal</p>
      <h1 class="page-title">Notes</h1>
      <p class="page-subtitle">Keep the important parts of the story within reach.</p>
    </header>

    <SessionImport @imported="onSessionImported" />

    <section class="threads-panel" aria-labelledby="threads-heading">
      <div class="threads-heading-row">
        <div>
          <p class="page-kicker">Between sessions</p>
          <h2 id="threads-heading">Open threads</h2>
        </div>
        <span class="thread-count">{{ threads.filter((thread) => !thread.is_done).length }} active</span>
      </div>
      <form class="thread-form" @submit.prevent="addThread">
        <input
          v-model="newThreadTitle"
          class="input"
          type="text"
          placeholder="Add a quest, question, or follow-up..."
          aria-label="New open thread"
        />
        <button type="submit" class="btn btn--primary">Add thread</button>
      </form>
      <div v-if="threadsLoading" class="thread-empty">Loading open threads...</div>
      <div v-else-if="threads.length === 0" class="thread-empty">
        No open threads yet. Capture the thing the party should remember next time.
      </div>
      <ul v-else class="thread-list">
        <li v-for="thread in threads" :key="thread.id" class="thread-row" :class="{ 'thread-row--done': thread.is_done }">
          <label class="thread-label">
            <input
              type="checkbox"
              :checked="thread.is_done"
              :aria-label="`Mark ${thread.title} ${thread.is_done ? 'open' : 'complete'}`"
              @change="toggleThread(thread)"
            />
            <span>{{ thread.title }}</span>
          </label>
          <button type="button" class="thread-delete" @click="deleteThread(thread)">Remove</button>
        </li>
      </ul>
    </section>

    <!-- Editor / New note — always at the top -->
    <article class="editor" :class="{ 'editor--reading': activeId && !isEditing }" aria-label="Campaign journal entry">
      <template v-if="activeId">
        <header class="editor-header">
          <div v-if="!isEditing" class="journal-heading">
            <p class="page-kicker">{{ activeNote?.noteType === 'session' ? 'Session chronicle' : activeNote?.noteType === 'transcript' ? 'Source archive' : 'Campaign journal' }}</p>
            <h2>{{ title || 'Untitled note' }}</h2>
            <span v-if="editorPlayedOn" class="journal-date">Played {{ editorPlayedOn }}</span>
          </div>
          <label v-if="isEditing" for="editor-title" class="visually-hidden">Note title</label>
          <input
            v-if="isEditing"
            id="editor-title"
            v-model="title"
            type="text"
            class="editor-title-input"
            placeholder="Title"
          />
          <div class="editor-toolbar">
            <span class="editor-status" aria-live="polite">
              {{ unsaved ? 'Unsaved changes' : 'Saved' }}
            </span>
            <div class="editor-actions">
              <div v-if="isMyNote(activeNote!)" class="journal-view-toggle" role="group" aria-label="Note view">
                <button type="button" :aria-pressed="!isEditing" @click="isEditing = false">Read</button>
                <button type="button" :aria-pressed="isEditing" @click="isEditing = true">Edit</button>
              </div>
              <template v-if="isMyNote(activeNote!) && unsaved">
                <button
                  type="button"
                  class="btn btn--secondary"
                  :disabled="!unsaved"
                  @click="saveActive"
                >
                  Save
                </button>
              </template>
              <button
                type="button"
                class="btn btn--outline"
                @click="activeId = null"
              >
                Close
              </button>
              <button
                v-if="isEditing && isMyNote(activeNote!)"
                type="button"
                class="btn btn--danger"
                aria-label="Delete this note"
                @click="deleteActive"
              >
                Delete
              </button>
            </div>
          </div>
        </header>

        <div v-if="isEditing && isMyNote(activeNote!) && activeNote?.noteType !== 'transcript'" class="shared-toggle">
          <label class="toggle-label">
            <input v-model="editorShared" type="checkbox" class="toggle-check" />
            <span class="toggle-text">{{ editorShared ? 'Shared with campaign' : 'Private note' }}</span>
          </label>
        </div>
        <div v-else class="shared-badge">{{ activeNote?.noteType === 'transcript' ? 'Private source transcript' : isMyNote(activeNote!) ? (editorShared ? 'Shared with campaign' : 'Private note') : 'Shared by another player' }}</div>

        <div v-if="isEditing || editorTags.length" class="editor-tags">
          <span class="editor-tags-label">Tags</span>
          <div class="editor-tags-list">
            <span
              v-for="(t, i) in editorTags"
              :key="t"
              class="tag"
            >
              {{ t }}
              <button
                v-if="isEditing"
                type="button"
                class="tag-remove"
                :aria-label="`Remove tag ${t}`"
                @click="removeTag(i)"
              >
                ×
              </button>
            </span>
            <input
              v-if="isEditing"
              v-model="newTagInput"
              type="text"
              class="tag-input"
              placeholder="Add tag"
              aria-label="Add tag"
              @keydown.enter.prevent="addTagFromInput()"
            />
            <button v-if="isEditing" type="button" class="btn btn--small" @click="addTagFromInput">
              Add
            </button>
          </div>
        </div>

        <template v-if="activeNote?.noteType === 'session'">
          <details v-if="isMyNote(activeNote)" class="recap-sharing">
            <summary>Share this session</summary>
            <strong>Share recap link</strong>
            <p>Anyone with the link can read the saved recap and stopping point. Future saved edits appear at the same link.</p>
            <template v-if="recapLink">
              <input class="input" :value="recapLink" readonly aria-label="Public recap link" @focus="($event.target as HTMLInputElement).select()" />
              <div class="new-note-actions">
                <button type="button" class="btn btn--secondary" @click="copyRecapLink">Copy link</button>
                <a :href="recapLink" target="_blank" rel="noopener noreferrer" class="btn btn--outline">Preview recap</a>
                <button type="button" class="btn btn--outline" :disabled="shareBusy" @click="setRecapLink(false)">Revoke link</button>
              </div>
            </template>
            <button v-else type="button" class="btn btn--secondary" :disabled="shareBusy || unsaved" @click="setRecapLink(true)">Create recap link</button>
          </details>
          <template v-if="isEditing">
          <label for="session-date">Played date (optional)</label>
          <input id="session-date" v-model="editorPlayedOn" class="input" type="date" :disabled="!isMyNote(activeNote)" />
          <label for="session-resume">Where we left off</label>
          <textarea id="session-resume" v-model="editorResumePoint" class="editor-body-input" rows="5" :readonly="!isMyNote(activeNote)" />
          </template>
          <aside v-else-if="editorResumePoint" class="journal-resume">
            <span class="page-kicker">Next session</span>
            <h3>Where we left off</h3>
            <MarkdownContent :content="editorResumePoint" />
          </aside>
          <RouterLink v-for="source in notes.filter(n => n.noteType === 'transcript' && n.parentSessionId === activeNote?.id)" :key="source.id" :to="{ path: '/notes', query: { note: source.id } }" @click="selectNote(source.id)">Open private source transcript</RouterLink>
        </template>
        <div v-if="!isEditing" class="journal-body">
          <pre v-if="activeNote?.noteType === 'transcript'" class="journal-transcript">{{ body }}</pre>
          <MarkdownContent v-else-if="body.trim()" :content="body" />
          <p v-else class="journal-empty">This page of the story is still unwritten.</p>
        </div>
        <label v-if="isEditing" for="editor-body" class="visually-hidden">Note content</label>
        <textarea
          v-if="isEditing"
          id="editor-body"
          v-model="body"
          class="editor-body-input"
          rows="12"
          placeholder="Write your note..."
        />
      </template>

      <template v-else>
        <header class="editor-header">
          <h2 class="editor-heading">New note</h2>
          <div class="editor-toolbar">
            <div class="editor-actions">
              <button type="button" class="btn btn--primary" @click="startSession">
                Start session
              </button>
              <button type="button" class="btn btn--secondary" @click="exportNotes">
                Export
              </button>
              <label class="btn btn--secondary btn--file">
                Import
                <input
                  type="file"
                  accept="application/json"
                  class="file-input"
                  aria-label="Import notes from JSON"
                  @change="onFileChange"
                />
              </label>
            </div>
          </div>
        </header>
        <div class="new-note-fields">
          <label for="new-title" class="visually-hidden">New note title</label>
          <input
            id="new-title"
            v-model="newTitle"
            type="text"
            class="input input--title"
            placeholder="Title"
            @keydown.enter.prevent="newBody && createNote()"
          />
          <label for="new-body" class="visually-hidden">New note content</label>
          <textarea
            id="new-body"
            v-model="newBody"
            class="input input--body"
            rows="4"
            placeholder="Write something..."
            @keydown.ctrl.enter.prevent="createNote()"
          />
          <div class="new-note-actions">
            <button type="button" class="btn btn--primary" @click="createNote()">
              Add note
            </button>
            <label class="toggle-label">
              <input v-model="newShared" type="checkbox" class="toggle-check" />
              <span class="toggle-text">{{ newShared ? 'Shared' : 'Private' }}</span>
            </label>
          </div>
        </div>
      </template>
    </article>

    <!-- Notes list with search and filters -->
    <section class="notes-panel" aria-label="Your notes">
      <header class="panel-header">
        <h2 class="section-heading">Campaign notes</h2>
        <form
          class="search-form"
          role="search"
          aria-label="Search notes"
          @submit.prevent
        >
          <label for="notes-search" class="visually-hidden">Search notes</label>
          <input
            id="notes-search"
            v-model="searchQuery"
            type="search"
            class="search-input"
            placeholder="Search..."
            autocomplete="off"
            aria-describedby="search-desc"
          />
          <span id="search-desc" class="visually-hidden">Matches title and body text</span>
        </form>
      </header>

      <div v-if="allTags.length > 0" class="filters">
        <span class="filters-label" id="filter-label">Filter by tag</span>
        <div class="tag-filters" role="group" aria-labelledby="filter-label">
          <button
            v-for="tag in allTags"
            :key="tag"
            type="button"
            class="tag-filter"
            :class="{ 'tag-filter--on': selectedTagFilters.includes(tag) }"
            :aria-pressed="selectedTagFilters.includes(tag)"
            @click="toggleTagFilter(tag)"
          >
            {{ tag }}
          </button>
          <button
            v-if="hasActiveFilters"
            type="button"
            class="tag-filter-clear"
            @click="clearFilters"
          >
            Clear
          </button>
        </div>
      </div>

      <div v-if="loading" class="empty-state">
        <p>Loading notes...</p>
      </div>
      <div v-else-if="notes.length === 0" class="empty-state">
        <p>No notes yet. Create one above.</p>
      </div>
      <div v-else-if="filteredNotes.length === 0" class="empty-state">
        <p>No notes match your search or filters.</p>
      </div>
      <ul v-else class="notes-grid" role="list">
        <li
          v-for="n in filteredNotes"
          :key="n.id"
          class="note-card"
          :class="{ 'note-card--active': n.id === activeId }"
        >
          <button
            type="button"
            class="note-card-button"
            :aria-current="n.id === activeId ? 'true' : undefined"
            @click="selectNote(n.id)"
          >
            <span class="note-card-title">
              {{ n.title }}
              <span v-if="n.isShared && !isMyNote(n)" class="shared-indicator">shared</span>
              <span v-else-if="n.isShared" class="shared-indicator shared-indicator--mine">shared</span>
            </span>
            <span v-if="n.tags.length" class="note-card-tags">
              <span
                v-for="t in n.tags.slice(0, 3)"
                :key="t"
                class="note-card-tag"
              >
                {{ t }}
              </span>
            </span>
            <time
              class="note-card-time"
              :datetime="new Date(n.updatedAt).toISOString()"
            >
              {{ formatDate(n.updatedAt) }}
            </time>
          </button>
          <button
            v-if="isMyNote(n)"
            type="button"
            class="note-card-delete"
            aria-label="Delete this note"
            @click.stop="deleteNote(n.id)"
          >
            Delete
          </button>
        </li>
      </ul>
    </section>
  </main>
</template>

<style scoped>
.editor--reading { border-top-color: var(--dnd-accent-2); }
.journal-heading { flex: 1; min-width: 0; }
.journal-heading .page-kicker { margin-bottom: .65rem; }
.journal-heading h2 { font-family: 'Spectral', serif; font-size: clamp(1.65rem, 3.5vw, 2.4rem); line-height: 1.25; color: var(--dnd-ink); margin: 0 0 .75rem; text-wrap: balance; overflow-wrap: anywhere; }
.journal-date { color: var(--dnd-muted); font-size: .85rem; }
.journal-body { width: 100%; max-width: 48rem; margin: .5rem auto 1.5rem; }
.journal-resume { width: 100%; max-width: 48rem; box-sizing: border-box; margin: .75rem auto; padding: 1.4rem; border-inline-start: 3px solid var(--dnd-accent-2); border-radius: 8px; background: var(--dnd-input-bg); }
.journal-resume h3 { font-family: 'Spectral', serif; font-size: 1.4rem; margin: .35rem 0 1rem; }
.journal-view-toggle { display: flex; padding: .2rem; border: 1px solid color-mix(in srgb, var(--dnd-muted) 30%, transparent); border-radius: 8px; background: var(--dnd-input-bg); }
.journal-view-toggle button { border: 0; border-radius: 5px; padding: .4rem .8rem; color: var(--dnd-muted); background: transparent; font: inherit; font-size: .85rem; cursor: pointer; }
.journal-view-toggle button[aria-pressed=true] { background: var(--dnd-elevated); color: var(--dnd-ink); box-shadow: 0 1px 5px #0002; }
.journal-transcript { white-space: pre-wrap; overflow-wrap: anywhere; font: .9rem/1.8 ui-monospace, monospace; color: var(--dnd-muted); }
.journal-empty { padding: 2rem 0; color: var(--dnd-muted); font-style: italic; }
.recap-sharing summary { cursor: pointer; color: var(--dnd-accent); font-size: .9rem; font-weight: 600; }

.recap-sharing { padding: 1rem; border: 1px solid var(--dnd-muted); border-radius: 8px; }
.recap-sharing p { color: var(--dnd-muted); line-height: 1.5; }
.recap-sharing .new-note-actions { margin-top: .75rem; }

.notes-page {
  --notes-space-xs: 0.25rem;
  --notes-space-sm: 0.5rem;
  --notes-space-md: 1rem;
  --notes-space-lg: 1.5rem;
  --notes-space-xl: 2rem;
  --notes-radius: 8px;
  --notes-radius-lg: 10px;
  --notes-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  --notes-shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.08);
  --notes-border: 1px solid rgba(0, 0, 0, 0.08);
  --notes-focus: 2px solid var(--dnd-accent);
  --notes-focus-offset: 2px;
}

.campaign-context {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  padding: 0.65rem 0.8rem;
  border: 1px solid rgba(32, 36, 42, 0.1);
  border-radius: 8px;
  background: var(--dnd-elevated);
  font-size: 0.78rem;
}

.session-mode-bar {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 1rem;
  padding: 0.9rem 1rem;
  border: 1px solid rgba(169, 76, 61, 0.3);
  border-radius: 8px;
  background: rgba(169, 76, 61, 0.08);
}

.session-mode-bar .page-kicker {
  margin: 0 0 0.15rem;
}

.session-mode-bar strong {
  display: block;
  color: var(--dnd-ink);
  font-family: 'Spectral', serif;
  font-size: 0.95rem;
}

.quick-capture {
  display: flex;
  gap: 0.4rem;
  min-width: 0;
}

.quick-capture input,
.quick-capture select {
  min-width: 0;
  padding: 0.45rem 0.6rem;
  border: 1px solid rgba(32, 36, 42, 0.14);
  border-radius: 6px;
  background: var(--dnd-input-bg);
  color: var(--dnd-ink);
  font: inherit;
}

.quick-capture input {
  flex: 1;
}

.session-mode-close {
  border: 0;
  background: transparent;
  color: var(--dnd-muted);
  cursor: pointer;
  font: inherit;
  font-size: 0.75rem;
}

.context-home {
  color: var(--dnd-ink);
  font-family: 'Spectral', serif;
  font-size: 0.95rem;
  font-weight: 700;
}

.context-divider {
  color: var(--dnd-accent-2);
}

.context-current {
  color: var(--dnd-muted);
}

.context-links {
  display: flex;
  gap: 0.25rem;
  margin-left: auto;
}

.context-link {
  padding: 0.3rem 0.5rem;
  border-radius: 5px;
  color: var(--dnd-muted);
  font-size: 0.7rem;
  font-weight: 700;
}

.context-link:hover {
  color: var(--dnd-accent);
  background: rgba(169, 76, 61, 0.08);
}

.notes-page {
  min-height: 100%;
  width: 100%;
  min-width: 0;
  padding: var(--notes-space-lg);
  max-width: 1120px;
  margin-inline: auto;
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-xl);
}

/* Flex and grid children must be allowed to shrink below their content width. */
.notes-page > *,
.notes-panel > *,
.editor > * {
  min-width: 0;
}

.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}

.page-title {
  font-family: 'Spectral', serif;
  font-size: clamp(2.1rem, 4vw, 3rem);
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
  letter-spacing: -0.03em;
}

.page-intro {
  padding: 0.75rem 0.25rem 0;
}

.page-kicker {
  color: var(--dnd-accent);
  font-size: 0.7rem;
  font-weight: 700;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin: 0 0 0.45rem;
}

.page-subtitle {
  color: var(--dnd-muted);
  font-size: 0.95rem;
  margin: 0.35rem 0 0;
}

.threads-panel {
  padding: 1.25rem;
  background: var(--dnd-elevated);
  border: 1px solid rgba(32, 36, 42, 0.1);
  border-top: 3px solid var(--dnd-accent-2);
  border-radius: 10px;
}

.threads-heading-row {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 0.9rem;
}

.threads-heading-row .page-kicker {
  margin-bottom: 0.2rem;
}

.threads-heading-row h2 {
  color: var(--dnd-ink);
  font-family: 'Spectral', serif;
  font-size: 1.55rem;
  line-height: 1;
  margin: 0;
}

.thread-count {
  color: var(--dnd-accent);
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.thread-form {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 0.75rem;
}

.thread-form .input {
  flex: 1;
}

.thread-empty {
  color: var(--dnd-muted);
  font-size: 0.82rem;
  padding: 0.7rem 0 0.2rem;
}

.thread-list {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  list-style: none;
  margin: 0;
  padding: 0;
}

.thread-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.55rem 0.65rem;
  border-radius: 6px;
  background: var(--dnd-input-bg);
}

.thread-label {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  min-width: 0;
  color: var(--dnd-ink);
  font-size: 0.84rem;
}

.thread-label input {
  flex-shrink: 0;
  accent-color: var(--dnd-accent);
}

.thread-row--done .thread-label {
  color: var(--dnd-muted);
  text-decoration: line-through;
}

.thread-delete {
  flex-shrink: 0;
  border: 0;
  background: transparent;
  color: var(--dnd-muted);
  cursor: pointer;
  font-family: inherit;
  font-size: 0.7rem;
}

.thread-delete:hover {
  color: var(--dnd-accent);
}

/* ----- Editor (top section) ----- */
.editor {
  padding: var(--notes-space-xl);
  background: var(--dnd-elevated);
  border-radius: var(--notes-radius-lg);
  box-shadow: var(--notes-shadow-lg);
  border: var(--notes-border);
  border-top: 3px solid var(--dnd-accent-2);
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-lg);
}

.editor-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--notes-space-md);
}

.editor-heading {
  font-family: 'Spectral', serif;
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
  flex: 1;
}

.editor-title-input {
  flex: 1;
  min-width: 12rem;
  padding: var(--notes-space-sm) var(--notes-space-md);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-input-bg);
  color: var(--dnd-ink);
  font-size: 1.25rem;
  font-weight: 600;
  font-family: inherit;
}
.editor-title-input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.12);
}

.editor-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--notes-space-md);
}
.editor-status {
  font-size: 0.8125rem;
  color: var(--dnd-muted);
}
.editor-actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--notes-space-sm);
}

.editor-tags {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--notes-space-sm);
}
.editor-tags-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--dnd-muted);
}
.editor-tags-list {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--notes-space-sm);
}

.tag {
  display: inline-flex;
  align-items: center;
  gap: 0.2rem;
  padding: var(--notes-space-xs) var(--notes-space-sm);
  border-radius: var(--notes-radius);
  background: rgba(0, 0, 0, 0.05);
  border: var(--notes-border);
  font-size: 0.8125rem;
  color: var(--dnd-ink);
}
.tag-remove {
  padding: 0 0.15rem;
  border: none;
  background: none;
  color: var(--dnd-muted);
  font-size: 1rem;
  line-height: 1;
  cursor: pointer;
  border-radius: 2px;
}
.tag-remove:hover {
  color: #b33a2a;
  background: rgba(179, 58, 42, 0.1);
}
.tag-input {
  min-width: 5rem;
  padding: var(--notes-space-xs) var(--notes-space-sm);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-input-bg);
  color: var(--dnd-ink);
  font-size: 0.875rem;
}
.tag-input:focus {
  outline: none;
  border-color: var(--dnd-accent);
}

.editor-body-input {
  width: 100%;
  min-height: 14rem;
  padding: var(--notes-space-md);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-input-bg);
  color: var(--dnd-ink);
  font-size: 0.9375rem;
  line-height: 1.6;
  font-family: ui-monospace, 'SF Mono', Menlo, Monaco, 'Roboto Mono', monospace;
  resize: vertical;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.editor-body-input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.12);
}

/* New note form (shown when no note is selected) */
.new-note-fields {
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-sm);
}

.input {
  width: 100%;
  padding: var(--notes-space-sm) var(--notes-space-md);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-input-bg);
  color: var(--dnd-ink);
  font-size: 0.9375rem;
  font-family: inherit;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.input::placeholder {
  color: var(--dnd-muted);
}
.input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.12);
}
.input--body {
  resize: vertical;
  min-height: 5rem;
  font-family: ui-monospace, 'SF Mono', Menlo, Monaco, 'Roboto Mono', monospace;
  font-size: 0.875rem;
}

.new-note-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--notes-space-sm);
}

/* ----- Buttons ----- */
.btn {
  padding: var(--notes-space-sm) var(--notes-space-md);
  border-radius: var(--notes-radius);
  border: none;
  font-size: 0.875rem;
  font-weight: 600;
  cursor: pointer;
  font-family: inherit;
  transition: background 0.15s, color 0.15s, opacity 0.15s;
}
.btn:focus-visible {
  outline: var(--notes-focus);
  outline-offset: var(--notes-focus-offset);
}
.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.btn--primary {
  background: var(--dnd-accent);
  color: var(--dnd-on-accent);
}
.btn--primary:hover:not(:disabled) {
  filter: brightness(1.08);
}
.btn--secondary {
  background: var(--dnd-accent-2);
  color: var(--dnd-on-accent);
}
.btn--secondary:hover:not(:disabled) {
  filter: brightness(1.06);
}
.btn--outline {
  background: transparent;
  color: var(--dnd-muted);
  border: var(--notes-border);
}
.btn--outline:hover:not(:disabled) {
  background: rgba(0, 0, 0, 0.04);
  color: var(--dnd-ink);
}
.btn--danger {
  background: #b33a2a;
  color: #fff;
}
.btn--danger:hover:not(:disabled) {
  filter: brightness(1.1);
}
.btn--small {
  padding: var(--notes-space-xs) var(--notes-space-sm);
  font-size: 0.8125rem;
}
.btn--file {
  cursor: pointer;
  margin: 0;
}
.file-input {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
}

/* ----- Notes panel (below editor) ----- */
.notes-panel {
  padding: var(--notes-space-xl);
  background: var(--dnd-elevated);
  border-radius: var(--notes-radius-lg);
  box-shadow: var(--notes-shadow-lg);
  border: var(--notes-border);
  border-top: 3px solid #637b9b;
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-md);
}

.panel-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--notes-space-md);
}

.panel-header .section-heading {
  margin: 0;
  flex-shrink: 0;
}

.section-heading {
  font-size: 0.8125rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--dnd-ink);
  margin: 0;
}

.search-form {
  flex: 1;
  min-width: 10rem;
  max-width: 20rem;
}

.search-input {
  width: 100%;
  padding: var(--notes-space-sm) var(--notes-space-md);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-input-bg);
  color: var(--dnd-ink);
  font-size: 0.9375rem;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.search-input::placeholder {
  color: var(--dnd-muted);
}
.search-input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.15);
}

.filters {
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-xs);
}
.filters-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--dnd-muted);
}
.tag-filters {
  display: flex;
  flex-wrap: wrap;
  gap: var(--notes-space-xs);
}
.tag-filter {
  padding: var(--notes-space-xs) var(--notes-space-sm);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: rgba(0, 0, 0, 0.03);
  color: var(--dnd-ink);
  font-size: 0.8125rem;
  cursor: pointer;
  transition: background 0.15s, border-color 0.15s, color 0.15s;
}
.tag-filter:hover {
  background: rgba(0, 0, 0, 0.06);
}
.tag-filter:focus-visible {
  outline: var(--notes-focus);
  outline-offset: var(--notes-focus-offset);
}
.tag-filter--on {
  background: var(--dnd-accent);
  border-color: var(--dnd-accent);
  color: var(--dnd-on-accent);
}
.tag-filter-clear {
  padding: var(--notes-space-xs) var(--notes-space-sm);
  border: none;
  background: none;
  color: var(--dnd-muted);
  font-size: 0.8125rem;
  cursor: pointer;
}
.tag-filter-clear:hover {
  color: var(--dnd-ink);
}

.empty-state {
  padding: var(--notes-space-lg);
  text-align: center;
  color: var(--dnd-muted);
  font-size: 0.9375rem;
  line-height: 1.5;
}
.empty-state p {
  margin: 0;
}

/* Notes grid — cards in a responsive grid */
.notes-grid {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 250px), 1fr));
  gap: var(--notes-space-md);
}

.note-card {
  min-width: 0;
  max-width: 100%;
  display: flex;
  flex-direction: column;
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-input-bg);
  border-top: 2px solid transparent;
  transition: background 0.12s, border-color 0.15s, box-shadow 0.15s;
}
.note-card:hover {
  background: rgba(0, 0, 0, 0.04);
  border-color: var(--dnd-accent-2);
  border-top-color: var(--dnd-accent-2);
  box-shadow: var(--notes-shadow);
}
.note-card--active {
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 2px rgba(139, 58, 47, 0.15);
  background: rgba(0, 0, 0, 0.04);
}

.note-card-button {
  width: 100%;
  max-width: 100%;
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: var(--notes-space-xs);
  padding: var(--notes-space-md);
  border: none;
  background: none;
  color: inherit;
  font-family: inherit;
  text-align: start;
  cursor: pointer;
  border-radius: var(--notes-radius) var(--notes-radius) 0 0;
  min-width: 0;
}
.note-card-button:focus-visible {
  outline: var(--notes-focus);
  outline-offset: var(--notes-focus-offset);
}

.note-card-title {
  display: block;
  width: 100%;
  min-width: 0;
  font-weight: 600;
  font-size: 0.9375rem;
  line-height: 1.3;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
}

.note-card-tags {
  display: flex;
  flex-wrap: wrap;
  gap: var(--notes-space-xs);
}
.note-card-tag {
  max-width: 100%;
  overflow-wrap: anywhere;
  font-size: 0.6875rem;
  padding: 0.1rem 0.35rem;
  border-radius: 4px;
  background: rgba(0, 0, 0, 0.06);
  color: var(--dnd-muted);
}

.note-card-time {
  font-size: 0.75rem;
  color: var(--dnd-muted);
}

.note-card-delete {
  padding: var(--notes-space-xs) var(--notes-space-md);
  border: none;
  border-top: var(--notes-border);
  background: none;
  color: var(--dnd-muted);
  font-size: 0.8125rem;
  cursor: pointer;
  text-align: center;
  border-radius: 0 0 var(--notes-radius) var(--notes-radius);
}
.note-card-delete:hover {
  color: #b33a2a;
  background: rgba(179, 58, 42, 0.08);
}

/* Shared toggle / badge */
.shared-toggle {
  display: flex;
  align-items: center;
}
.toggle-label {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  cursor: pointer;
  font-size: 0.8125rem;
  color: var(--dnd-ink);
}
.toggle-check {
  accent-color: var(--dnd-accent);
}
.toggle-text {
  user-select: none;
}
.shared-badge {
  font-size: 0.8rem;
  color: var(--dnd-muted);
  font-style: italic;
}
.shared-indicator {
  font-size: 0.6rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  background: rgba(0, 0, 0, 0.08);
  color: var(--dnd-muted);
  padding: 0.05rem 0.3rem;
  border-radius: 4px;
  vertical-align: middle;
  margin-left: 0.3rem;
}
.shared-indicator--mine {
  background: rgba(139, 58, 47, 0.12);
  color: var(--dnd-accent);
}

/* Dark theme: visible borders + tinted surfaces (light theme keeps default tokens) */
:global(.dark) .notes-page {
  --notes-border: 1px solid rgba(255, 255, 255, 0.12);
  --notes-shadow: 0 2px 12px rgba(0, 0, 0, 0.45);
  --notes-shadow-lg: 0 8px 36px rgba(0, 0, 0, 0.55);
}

:global(.dark) .notes-page .tag {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.1);
}

:global(.dark) .notes-page .tag-filter {
  background: rgba(255, 255, 255, 0.05);
  border-color: rgba(255, 255, 255, 0.1);
}

:global(.dark) .notes-page .tag-filter:hover {
  background: rgba(255, 255, 255, 0.09);
}

:global(.dark) .notes-page .note-card {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.1);
}

:global(.dark) .notes-page .note-card:hover {
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(255, 255, 255, 0.16);
}

:global(.dark) .notes-page .note-card--active {
  border-color: var(--dnd-accent);
  background: rgba(201, 107, 90, 0.14);
  box-shadow: 0 0 0 1px rgba(201, 107, 90, 0.35);
}

:global(.dark) .notes-page .note-card-tag {
  background: rgba(255, 255, 255, 0.08);
}

:global(.dark) .notes-page .shared-indicator {
  background: rgba(255, 255, 255, 0.1);
}

:global(.dark) .notes-page .btn--outline:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.06);
  color: var(--dnd-ink);
}

@media (max-width: 600px) {
  .notes-page {
    padding: var(--notes-space-md);
  }
  .campaign-context {
    flex-wrap: wrap;
  }
  .session-mode-bar {
    grid-template-columns: 1fr auto;
  }
  .quick-capture {
    grid-column: 1 / -1;
    grid-row: 2;
  }
  .thread-form {
    flex-direction: column;
  }
  .context-links {
    width: 100%;
    margin-left: 0;
    padding-top: 0.35rem;
    border-top: 1px solid rgba(32, 36, 42, 0.08);
  }
  .editor-header {
    flex-direction: column;
    align-items: stretch;
  }
  .editor-title-input {
    min-width: 0;
  }
  .panel-header {
    flex-direction: column;
    align-items: stretch;
  }
  .search-form {
    max-width: none;
  }
  .notes-grid {
    grid-template-columns: minmax(0, 1fr);
  }
  .editor,
  .notes-panel,
  .threads-panel {
    padding: var(--notes-space-md);
  }
  .note-card-title {
    white-space: normal;
    overflow-wrap: anywhere;
    text-overflow: clip;
    line-height: 1.45;
  }
  .thread-label span,
  .tag,
  .tag-filter,
  .context-home {
    overflow-wrap: anywhere;
  }
  .tag,
  .tag-filter {
    max-width: 100%;
  }
  .context-links,
  .quick-capture {
    flex-wrap: wrap;
  }
  .quick-capture input {
    flex-basis: 100%;
    order: -1;
  }
  .editor-toolbar,
  .editor-actions {
    min-width: 0;
    max-width: 100%;
  }
  .search-form {
    min-width: 0;
    width: 100%;
  }
}
</style>
