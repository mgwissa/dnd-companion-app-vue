<script setup lang="ts">
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { showToast, clearToastTimer } from '@/composables/useToast'

type Note = { id: string; title: string; body: string; updatedAt: number }

const STORAGE_KEY = 'dnd_notes_v1'

const notes = ref<Note[]>([])
const activeId = ref<string | null>(null)

// editor fields (detached from the source note so we can show "Unsaved changes")
const title = ref('')
const body = ref('')

// new note inputs
const newTitle = ref('')
const newBody = ref('')

function uid() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

function saveNotesToStorage() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(notes.value))
  } catch (e) {
    console.warn('Failed to save notes', e)
  }
}

function loadNotesFromStorage() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return
    const parsed = JSON.parse(raw) as Note[]
    // basic shape guard
    notes.value = parsed
      .filter((n) => typeof n.id === 'string')
      .map((n) => ({ ...n, updatedAt: Number(n.updatedAt) || Date.now() }))
      .sort((a, b) => b.updatedAt - a.updatedAt)
  } catch (e) {
    console.warn('Failed to load notes', e)
  }
}

function createNote() {
  const n: Note = {
    id: uid(),
    title: newTitle.value.trim() || `Untitled ${notes.value.length + 1}`,
    body: newBody.value,
    updatedAt: Date.now(),
  }
  notes.value.unshift(n)
  selectNote(n.id)
  // clear inputs
  newTitle.value = ''
  newBody.value = ''
  showToast('Created', 'success')
}

function selectNote(id: string) {
  const n = notes.value.find((x) => x.id === id)
  if (!n) return
  activeId.value = id
  // load into editor
  title.value = n.title
  body.value = n.body
}

function deleteNote(id: string) {
  const i = notes.value.findIndex((x) => x.id === id)
  if (i === -1) return
  notes.value.splice(i, 1)
  if (activeId.value === id) {
    activeId.value = null
    title.value = ''
    body.value = ''
  }
  showToast('Deleted', 'error')
}

function exportNotes() {
  const data = JSON.stringify(notes.value, null, 2)
  const blob = new Blob([data], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'dnd-notes.json'
  a.click()
  URL.revokeObjectURL(url)
  showToast('Exported notes', 'info')
}

function importNotes(file: File | null) {
  if (!file) return
  const reader = new FileReader()
  reader.onload = () => {
    try {
      const parsed = JSON.parse(String(reader.result)) as Note[]
      const byId = new Map(notes.value.map((n) => [n.id, n] as const))
      for (const n of parsed) {
        if (!n?.id) continue
        const existing = byId.get(n.id)
        const incoming = { ...n, updatedAt: Number(n.updatedAt) || Date.now() }
        if (!existing || incoming.updatedAt > existing.updatedAt) {
          byId.set(n.id, incoming)
        }
      }
      notes.value = Array.from(byId.values()).sort((a, b) => b.updatedAt - a.updatedAt)
      // if current active was merged, refresh editor fields
      if (activeId.value) {
        const cur = notes.value.find((n) => n.id === activeId.value)
        if (cur) {
          title.value = cur.title
          body.value = cur.body
        }
      }
      showToast('Imported', 'info')
    } catch (e) {
      console.warn('Failed to import notes', e)
    }
  }
  reader.readAsText(file)
}

function onFileChange(e: Event) {
  const input = e.target as HTMLInputElement | null
  const file = input?.files?.[0] ?? null
  importNotes(file)
}

function saveActive() {
  if (!activeId.value) return
  const i = notes.value.findIndex((x) => x.id === activeId.value)
  if (i === -1) return
  notes.value[i] = {
    ...notes.value[i],
    title: title.value,
    body: body.value,
    updatedAt: Date.now(),
  }
  showToast('Saved', 'success')
}

function deleteActive() {
  if (activeId.value) deleteNote(activeId.value)
  showToast('Deleted', 'error')
}

// persist to localStorage
watch(notes, saveNotesToStorage, { deep: true })

onMounted(() => {
  loadNotesFromStorage()
  // keyboard shortcut: Ctrl/Cmd+S to save
  const handler = (e: KeyboardEvent) => {
    const isSave = (e.ctrlKey || e.metaKey) && (e.key === 's' || e.code === 'KeyS')
    if (isSave) {
      e.preventDefault()
      saveActive()
    }
  }
  window.addEventListener('keydown', handler)
  // cleanup
  onBeforeUnmount(() => window.removeEventListener('keydown', handler))
})

onBeforeUnmount(() => {
  clearToastTimer()
})

const sortedNotes = computed(() => notes.value.slice().sort((a, b) => b.updatedAt - a.updatedAt))
const activeNote = computed(() => notes.value.find((n) => n.id === activeId.value) ?? null)
const unsaved = computed(() =>
  activeNote.value
    ? activeNote.value.title !== title.value || activeNote.value.body !== body.value
    : false,
)
</script>

<template>
  <main class="notes-root p-6 mx-auto">
    <h1 class="notes-title">Notes</h1>

    <section class="notes-grid">
      <aside class="notes-sidebar">
        <div class="mb-3">
          <input v-model="newTitle" placeholder="New note title" class="editor-title creator" />
        </div>
        <div class="mb-3">
          <textarea
            v-model="newBody"
            rows="4"
            placeholder="Write something..."
            class="editor-body creator resize-none"
          ></textarea>
        </div>
        <div class="notes-actions">
          <button class="btn primary" @click="createNote">Add</button>
          <button class="btn" @click="exportNotes">Export</button>
          <label class="btn cursor-pointer">
            Import
            <input type="file" accept="application/json" class="hidden" @change="onFileChange" />
          </label>
        </div>

        <hr class="my-3" />

        <div class="notes-list">
          <div v-if="sortedNotes.length === 0" class="notes-empty">No notes yet</div>

          <div
            v-for="n in sortedNotes"
            :key="n.id"
            class="note-row"
            :class="{ active: n.id === activeId }"
          >
            <button class="note-info" @click="selectNote(n.id)" :aria-pressed="n.id === activeId">
              <div class="note-title">{{ n.title }}</div>
              <div class="note-meta">{{ new Date(n.updatedAt).toLocaleString() }}</div>
            </button>
            <div class="note-actions">
              <button class="link-delete" @click="deleteNote(n.id)">Delete</button>
            </div>
          </div>
        </div>
      </aside>

      <section class="notes-editor">
        <div class="editor-head">
          <input v-model="title" placeholder="Title" class="editor-title" :disabled="!activeId" />
          <div class="editor-controls">
            <span class="status">
              {{ activeId ? (unsaved ? 'Unsaved changes' : 'Editing') : 'No note selected' }}
            </span>
            <div class="editor-buttons">
              <button class="btn" @click="saveActive" :disabled="!activeId">Save</button>
              <button class="btn danger" @click="deleteActive" :disabled="!activeId">Delete</button>
            </div>
          </div>
        </div>

        <div>
          <textarea
            v-model="body"
            rows="14"
            placeholder="Your note..."
            class="editor-body"
            :disabled="!activeId"
          ></textarea>

          <!-- toast rendered by global <Toast/> component -->
        </div>
      </section>
    </section>
  </main>
</template>

<style scoped>
/* Desktop-first layout polish */
.notes-root {
  padding-top: 2.5rem;
}
.notes-title {
  font-family: 'Cinzel', serif;
  font-size: 2.25rem;
  margin-bottom: 1.5rem;
  color: var(--dnd-ink);
  text-align: center;
}

/* center the page and allow generous maximum width on large screens */
.notes-grid {
  display: grid;
  grid-template-columns: 380px minmax(640px, 1fr);
  gap: 3rem;
  max-width: 1400px;
  margin: 0 auto;
  width: calc(100% - 6rem);
  align-items: start;
}

.notes-sidebar {
  position: sticky;
  top: 3.5rem; /* keep below header/title */
  height: calc(100vh - 5rem);
  overflow: auto;
  background: linear-gradient(180deg, var(--dnd-paper) 0%, rgba(255, 255, 255, 0.02) 100%);
  padding: 1.25rem;
  border-radius: 12px;
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.18);
}

/* new-note input styles */
.notes-sidebar input[type='text'],
.notes-sidebar textarea {
  color: var(--dnd-ink);
  border: 1px solid rgba(0, 0, 0, 0.08);
  padding: 0.6rem;
  border-radius: 6px;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.02);
}
.notes-sidebar textarea {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, 'Roboto Mono', monospace;
}
.notes-sidebar input[type='text']:focus,
.notes-sidebar textarea:focus {
  outline: none;
  border-color: rgba(0, 0, 0, 0.18);
  box-shadow: 0 4px 18px rgba(0, 0, 0, 0.08);
}
.notes-sidebar .notes-actions .btn {
  min-width: 84px;
}

/* creator variant: match editor look but smaller for the sidebar creator */
.editor-title.creator {
  width: 100%;
  font-size: 0.95rem;
  padding: 0.5rem;
  border-radius: 6px;
}
.editor-body.creator {
  min-height: 5.5rem;
  max-height: 9rem;
  padding: 0.8rem;
  border-radius: 8px;
}

.notes-actions {
  display: flex;
  gap: 0.6rem;
  margin-bottom: 0.75rem;
  align-items: center;
}
.btn {
  border-radius: 10px;
  padding: 0.5rem 0.9rem;
  border: none;
}
.btn.primary {
  background: var(--dnd-accent);
  color: var(--dnd-paper);
}
.btn:not(.primary) {
  background: var(--dnd-accent-2);
  color: var(--dnd-paper);
}
.btn.danger {
  background: #b33a2a;
}

.notes-list {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  margin-top: 0.5rem;
}
.notes-empty {
  color: var(--dnd-muted);
  padding: 1rem;
}

.note-row {
  display: flex;
  gap: 0.75rem;
  align-items: flex-start;
  justify-content: space-between;
  padding: 12px;
  border-radius: 10px;
  background: transparent;
  transition:
    background 0.12s,
    transform 0.06s;
}
.note-row.active {
  background: linear-gradient(90deg, rgba(0, 0, 0, 0.04), rgba(0, 0, 0, 0.02));
  box-shadow: inset 0 0 0 2px rgba(0, 0, 0, 0.03);
}
.note-row:hover {
  background: rgba(0, 0, 0, 0.04);
  transform: translateY(-1px);
}

.note-info {
  display: block;
  text-align: left;
  background: transparent;
  border: none;
  padding: 0;
  margin: 0;
  width: 100%;
}
.note-title {
  font-weight: 800;
  font-size: 1.02rem;
  line-height: 1.2;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.note-meta {
  font-size: 0.78rem;
  color: var(--dnd-muted);
  margin-top: 6px;
}
.note-preview {
  display: block;
  color: var(--dnd-muted);
  font-size: 0.9rem;
  margin-top: 6px;
  max-height: 38px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.link-delete {
  background: transparent;
  border: none;
  color: #b33a2a;
  padding: 0.25rem 0.5rem;
}

.notes-editor {
  background: var(--dnd-paper);
  padding: 1.5rem;
  border-radius: 12px;
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.18);
}
.editor-head {
  display: flex;
  gap: 1rem;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 1rem;
}
.editor-title {
  font-size: 1.25rem;
  padding: 0.7rem;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  width: 60%;
}
.editor-controls {
  display: flex;
  gap: 1rem;
  align-items: center;
}
.status {
  color: var(--dnd-muted);
}
.editor-buttons {
  display: flex;
  gap: 0.6rem;
}

.editor-body {
  width: 100%;
  min-height: 72vh;
  max-height: 84vh;
  padding: 1.1rem;
  border-radius: 10px;
  border: 1px solid rgba(0, 0, 0, 0.07);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, 'Roboto Mono', monospace;
  resize: vertical;
}

/* responsive fallbacks */
@media (max-width: 1100px) {
  .notes-grid {
    grid-template-columns: 1fr;
    width: calc(100% - 3rem);
    gap: 1.25rem;
  }
  .notes-sidebar {
    position: relative;
    height: auto;
  }
  .editor-title {
    width: 100%;
  }
  .editor-body {
    min-height: 56vh;
  }
}

/* toast styles moved to src/components/Toast.vue */
</style>
