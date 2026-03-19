<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { showToast, clearToastTimer } from '@/composables/useToast'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'

type Note = { id: string; title: string; body: string; updatedAt: number; tags: string[] }

interface DbNote {
  id: string
  user_id: string
  title: string
  body: string
  tags: string[]
  updated_at: string
  created_at: string
}

function dbToNote(row: DbNote): Note {
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    tags: row.tags ?? [],
    updatedAt: new Date(row.updated_at).getTime(),
  }
}

const auth = useAuthStore()

const notes = ref<Note[]>([])
const activeId = ref<string | null>(null)
const loading = ref(false)

const title = ref('')
const body = ref('')
const editorTags = ref<string[]>([])

const searchQuery = ref('')
const selectedTagFilters = ref<string[]>([])
const newTagInput = ref('')

const newTitle = ref('')
const newBody = ref('')

async function fetchNotes() {
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('notes')
      .select('*')
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

async function createNote() {
  const noteTitle = newTitle.value.trim() || `Untitled ${notes.value.length + 1}`
  const noteBody = newBody.value

  try {
    const { data, error } = await supabase
      .from('notes')
      .insert({
        user_id: auth.user!.id,
        title: noteTitle,
        body: noteBody,
        tags: [],
        updated_at: new Date().toISOString(),
      })
      .select()
      .single()
    if (error) throw error

    const n = dbToNote(data as DbNote)
    notes.value.unshift(n)
    selectNote(n.id)
    newTitle.value = ''
    newBody.value = ''
    showToast('Created', 'success')
  } catch (e) {
    console.warn('Failed to create note', e)
    showToast('Failed to create note', 'error')
  }
}

function selectNote(id: string) {
  const n = notes.value.find((x) => x.id === id)
  if (!n) return
  activeId.value = id
  title.value = n.title
  body.value = n.body
  editorTags.value = [...n.tags]
}

async function deleteNote(id: string) {
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
  a.download = 'dnd-notes.json'
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
        title: n.title ?? '',
        body: n.body ?? '',
        tags: Array.isArray(n.tags) ? n.tags : [],
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

  const now = new Date()
  try {
    const { error } = await supabase
      .from('notes')
      .update({
        title: title.value,
        body: body.value,
        tags: [...editorTags.value],
        updated_at: now.toISOString(),
      })
      .eq('id', activeId.value)
    if (error) throw error

    notes.value[i] = {
      ...notes.value[i],
      title: title.value,
      body: body.value,
      tags: [...editorTags.value],
      updatedAt: now.getTime(),
    }
    showToast('Saved', 'success')
  } catch (e) {
    console.warn('Failed to save note', e)
    showToast('Failed to save note', 'error')
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

onMounted(() => {
  fetchNotes()
  const handler = (e: KeyboardEvent) => {
    const isSave = (e.ctrlKey || e.metaKey) && (e.key === 's' || e.code === 'KeyS')
    if (isSave) {
      e.preventDefault()
      saveActive()
    }
  }
  window.addEventListener('keydown', handler)
  onBeforeUnmount(() => window.removeEventListener('keydown', handler))
})

onBeforeUnmount(() => {
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
  return !tagsEqual(activeNote.value.tags, editorTags.value)
})
</script>

<template>
  <main class="notes-page" role="main">
    <div class="notes-layout">
      <!-- Sidebar: search, filters, new note form, list -->
      <aside class="sidebar" aria-label="Notes list and actions">
        <header class="sidebar-header">
          <h1 class="page-title">Notes</h1>
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
        </header>

        <section class="new-note" aria-labelledby="new-note-heading">
          <h2 id="new-note-heading" class="section-heading">New note</h2>
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
              rows="3"
              placeholder="Write something..."
              @keydown.ctrl.enter.prevent="createNote()"
            />
            <div class="new-note-actions">
              <button type="button" class="btn btn--primary" @click="createNote">
                Add note
              </button>
              <div class="toolbar-group">
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
          </div>
        </section>

        <nav class="notes-nav" aria-label="Your notes">
          <h2 class="section-heading">Your notes</h2>
          <div v-if="loading" class="empty-state">
            <p>Loading notes...</p>
          </div>
          <div v-else-if="notes.length === 0" class="empty-state">
            <p>No notes yet. Create one above.</p>
          </div>
          <div v-else-if="filteredNotes.length === 0" class="empty-state">
            <p>No notes match your search or filters.</p>
          </div>
          <ul v-else class="notes-list" role="list">
            <li
              v-for="n in filteredNotes"
              :key="n.id"
              class="note-item"
              :class="{ 'note-item--active': n.id === activeId }"
            >
              <button
                type="button"
                class="note-item-button"
                :aria-current="n.id === activeId ? 'true' : undefined"
                @click="selectNote(n.id)"
              >
                <span class="note-item-title">{{ n.title }}</span>
                <span v-if="n.tags.length" class="note-item-tags">
                  <span
                    v-for="t in n.tags.slice(0, 3)"
                    :key="t"
                    class="note-item-tag"
                  >
                    {{ t }}
                  </span>
                </span>
                <time
                  class="note-item-time"
                  :datetime="new Date(n.updatedAt).toISOString()"
                >
                  {{ formatDate(n.updatedAt) }}
                </time>
              </button>
              <button
                type="button"
                class="note-item-delete"
                aria-label="Delete this note"
                @click.stop="deleteNote(n.id)"
              >
                Delete
              </button>
            </li>
          </ul>
        </nav>
      </aside>

      <!-- Editor -->
      <article
        class="editor"
        :class="{ 'editor--empty': !activeId }"
        aria-label="Note editor"
      >
        <template v-if="activeId">
          <header class="editor-header">
            <label for="editor-title" class="visually-hidden">Note title</label>
            <input
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
                <button
                  type="button"
                  class="btn btn--secondary"
                  :disabled="!unsaved"
                  @click="saveActive"
                >
                  Save
                </button>
                <button
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

          <div class="editor-tags">
            <span class="editor-tags-label">Tags</span>
            <div class="editor-tags-list">
              <span
                v-for="(t, i) in editorTags"
                :key="t"
                class="tag"
              >
                {{ t }}
                <button
                  type="button"
                  class="tag-remove"
                  :aria-label="`Remove tag ${t}`"
                  @click="removeTag(i)"
                >
                  ×
                </button>
              </span>
              <input
                v-model="newTagInput"
                type="text"
                class="tag-input"
                placeholder="Add tag"
                aria-label="Add tag"
                @keydown.enter.prevent="addTagFromInput()"
              />
              <button type="button" class="btn btn--small" @click="addTagFromInput">
                Add
              </button>
            </div>
          </div>

          <label for="editor-body" class="visually-hidden">Note content</label>
          <textarea
            id="editor-body"
            v-model="body"
            class="editor-body-input"
            rows="16"
            placeholder="Write your note..."
          />
        </template>
        <div v-else class="editor-empty">
          <p>Select a note from the list or create a new one.</p>
        </div>
      </article>
    </div>
  </main>
</template>

<style scoped>
/* Design tokens */
.notes-page {
  --notes-space-xs: 0.25rem;
  --notes-space-sm: 0.5rem;
  --notes-space-md: 1rem;
  --notes-space-lg: 1.5rem;
  --notes-space-xl: 2rem;
  --notes-radius: 8px;
  --notes-radius-lg: 12px;
  --notes-sidebar-width: 320px;
  --notes-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  --notes-shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.08);
  --notes-border: 1px solid rgba(0, 0, 0, 0.08);
  --notes-focus: 2px solid var(--dnd-accent);
  --notes-focus-offset: 2px;
}

.notes-page {
  min-height: 100%;
  padding: var(--notes-space-lg);
}

.notes-layout {
  display: grid;
  grid-template-columns: minmax(0, var(--notes-sidebar-width)) 1fr;
  gap: var(--notes-space-xl);
  max-width: 1200px;
  margin-inline: auto;
  align-items: start;
}

/* Visually hidden, still for screen readers */
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

/* ----- Sidebar ----- */
.sidebar {
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-lg);
  position: sticky;
  top: var(--notes-space-lg);
  max-height: calc(100vh - var(--notes-space-xl));
  overflow-y: auto;
  padding: var(--notes-space-lg);
  background: var(--dnd-paper);
  border-radius: var(--notes-radius-lg);
  box-shadow: var(--notes-shadow-lg);
  border: var(--notes-border);
}

.sidebar-header {
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-md);
}

.page-title {
  font-family: 'Cinzel', serif;
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0;
  letter-spacing: 0.02em;
}

.search-form {
  display: block;
}

.search-input {
  width: 100%;
  padding: var(--notes-space-sm) var(--notes-space-md);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-bg);
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
  color: var(--dnd-paper);
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

.section-heading {
  font-size: 0.8125rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--dnd-muted);
  margin: 0 0 var(--notes-space-sm);
}

.new-note {
  padding-block-end: var(--notes-space-lg);
  border-block-end: var(--notes-border);
}

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
  background: var(--dnd-bg);
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
  min-height: 4.5rem;
  font-family: ui-monospace, 'SF Mono', Menlo, Monaco, 'Roboto Mono', monospace;
  font-size: 0.875rem;
}

.new-note-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--notes-space-sm);
}
.toolbar-group {
  display: flex;
  gap: var(--notes-space-xs);
}

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
  color: var(--dnd-paper);
}
.btn--primary:hover:not(:disabled) {
  filter: brightness(1.08);
}
.btn--secondary {
  background: var(--dnd-accent-2);
  color: var(--dnd-paper);
}
.btn--secondary:hover:not(:disabled) {
  filter: brightness(1.06);
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

.notes-nav {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.notes-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-xs);
  overflow-y: auto;
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

.note-item {
  display: flex;
  align-items: stretch;
  gap: var(--notes-space-sm);
  border-radius: var(--notes-radius);
  transition: background 0.12s;
}
.note-item:hover {
  background: rgba(0, 0, 0, 0.04);
}
.note-item--active {
  background: rgba(0, 0, 0, 0.06);
  box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.08);
}

.note-item-button {
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
  border-radius: var(--notes-radius);
  min-width: 0;
}
.note-item-button:focus-visible {
  outline: var(--notes-focus);
  outline-offset: var(--notes-focus-offset);
}

.note-item-title {
  font-weight: 600;
  font-size: 0.9375rem;
  line-height: 1.3;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
}

.note-item-tags {
  display: flex;
  flex-wrap: wrap;
  gap: var(--notes-space-xs);
}
.note-item-tag {
  font-size: 0.6875rem;
  padding: 0.1rem 0.35rem;
  border-radius: 4px;
  background: rgba(0, 0, 0, 0.06);
  color: var(--dnd-muted);
}

.note-item-time {
  font-size: 0.75rem;
  color: var(--dnd-muted);
}

.note-item-delete {
  padding: var(--notes-space-xs) var(--notes-space-sm);
  border: none;
  background: none;
  color: var(--dnd-muted);
  font-size: 0.8125rem;
  cursor: pointer;
  align-self: center;
  border-radius: var(--notes-radius);
}
.note-item-delete:hover {
  color: #b33a2a;
  background: rgba(179, 58, 42, 0.08);
}

/* ----- Editor ----- */
.editor {
  min-height: 400px;
  padding: var(--notes-space-xl);
  background: var(--dnd-paper);
  border-radius: var(--notes-radius-lg);
  box-shadow: var(--notes-shadow-lg);
  border: var(--notes-border);
  display: flex;
  flex-direction: column;
  gap: var(--notes-space-lg);
}
.editor--empty {
  justify-content: center;
  align-items: center;
}

.editor-empty {
  color: var(--dnd-muted);
  font-size: 0.9375rem;
  text-align: center;
}
.editor-empty p {
  margin: 0;
}

.editor-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--notes-space-md);
}

.editor-title-input {
  flex: 1;
  min-width: 12rem;
  padding: var(--notes-space-sm) var(--notes-space-md);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-bg);
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
  background: var(--dnd-bg);
  color: var(--dnd-ink);
  font-size: 0.875rem;
}
.tag-input:focus {
  outline: none;
  border-color: var(--dnd-accent);
}

.editor-body-input {
  width: 100%;
  min-height: 20rem;
  padding: var(--notes-space-md);
  border-radius: var(--notes-radius);
  border: var(--notes-border);
  background: var(--dnd-bg);
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

/* Responsive: stack sidebar above editor */
@media (max-width: 768px) {
  .notes-layout {
    grid-template-columns: 1fr;
    gap: var(--notes-space-lg);
  }
  .sidebar {
    position: relative;
    top: 0;
    max-height: none;
  }
  .editor-header {
    flex-direction: column;
    align-items: stretch;
  }
  .editor-title-input {
    min-width: 0;
  }
}
</style>
