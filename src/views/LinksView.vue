<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { showToast } from '@/composables/useToast'

interface LinkItem {
  id: string
  label: string
  url: string
  order: number
}

const STORAGE_KEY = 'dnd_links_v1'

const links = ref<LinkItem[]>([])
const newLabel = ref('')
const newUrl = ref('')
const editingId = ref<string | null>(null)
const editLabel = ref('')
const editUrl = ref('')

function uid() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

function saveToStorage() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(links.value))
  } catch (e) {
    console.warn('Failed to save links', e)
  }
}

function loadFromStorage() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return
    const parsed = JSON.parse(raw) as LinkItem[]
    if (Array.isArray(parsed)) {
      links.value = parsed
        .filter((l) => l?.id && typeof l.label === 'string' && typeof l.url === 'string')
        .map((l) => ({ ...l, order: Number(l.order) || 0 }))
        .sort((a, b) => a.order - b.order)
    }
  } catch (e) {
    console.warn('Failed to load links', e)
  }
}

function addLink() {
  const label = newLabel.value.trim()
  const url = newUrl.value.trim()
  if (!label || !url) {
    showToast('Label and URL required', 'error')
    return
  }
  const withProtocol = url.match(/^https?:\/\//i) ? url : `https://${url}`
  links.value.push({
    id: uid(),
    label,
    url: withProtocol,
    order: links.value.length,
  })
  newLabel.value = ''
  newUrl.value = ''
  showToast('Link added', 'success')
}

function startEdit(link: LinkItem) {
  editingId.value = link.id
  editLabel.value = link.label
  editUrl.value = link.url
}

function saveEdit() {
  const id = editingId.value
  if (!id) return
  const item = links.value.find((l) => l.id === id)
  if (!item) return
  const label = editLabel.value.trim()
  const url = editUrl.value.trim()
  if (!label || !url) {
    showToast('Label and URL required', 'error')
    return
  }
  item.label = label
  item.url = url.match(/^https?:\/\//i) ? url : `https://${url}`
  editingId.value = null
  editLabel.value = ''
  editUrl.value = ''
  showToast('Link updated', 'success')
}

function cancelEdit() {
  editingId.value = null
  editLabel.value = ''
  editUrl.value = ''
}

function deleteLink(id: string) {
  links.value = links.value.filter((l) => l.id !== id)
  showToast('Link removed', 'info')
}

function openLink(url: string) {
  window.open(url, '_blank', 'noopener,noreferrer')
}

watch(links, saveToStorage, { deep: true })

onMounted(loadFromStorage)
</script>

<template>
  <main class="links-page">
    <h1 class="page-title">Useful links</h1>
    <p class="page-desc">
      Keep your character sheet, rules, and other in-game links in one place. Opens in a new tab.
    </p>

    <!-- Add new -->
    <section class="add-section">
      <h2 class="section-heading">Add link</h2>
      <div class="add-form">
        <input
          v-model="newLabel"
          type="text"
          class="input"
          placeholder="e.g. My character sheet"
          @keydown.enter="newUrl && addLink()"
        />
        <input
          v-model="newUrl"
          type="url"
          class="input input-url"
          placeholder="https://..."
          @keydown.enter="newLabel && addLink()"
        />
        <button type="button" class="btn primary" @click="addLink">Add</button>
      </div>
    </section>

    <!-- List -->
    <section class="list-section">
      <h2 class="section-heading">Your links</h2>
      <div v-if="links.length === 0" class="empty">No links yet. Add your character sheet or other handy links above.</div>
      <ul class="link-list">
        <li v-for="link in links" :key="link.id" class="link-item">
          <template v-if="editingId === link.id">
            <div class="edit-form">
              <input v-model="editLabel" type="text" class="input" placeholder="Label" />
              <input v-model="editUrl" type="url" class="input input-url" placeholder="URL" />
              <div class="edit-actions">
                <button type="button" class="btn" @click="saveEdit">Save</button>
                <button type="button" class="btn secondary" @click="cancelEdit">Cancel</button>
              </div>
            </div>
          </template>
          <template v-else>
            <a
              :href="link.url"
              target="_blank"
              rel="noopener noreferrer"
              class="link-card"
              @click.prevent="openLink(link.url)"
            >
              <span class="link-label">{{ link.label }}</span>
              <span class="link-url">{{ link.url }}</span>
            </a>
            <div class="item-actions">
              <button type="button" class="btn-icon" title="Edit" @click="startEdit(link)">Edit</button>
              <button type="button" class="btn-icon danger" title="Remove" @click="deleteLink(link.id)">Remove</button>
            </div>
          </template>
        </li>
      </ul>
    </section>
  </main>
</template>

<style scoped>
.links-page {
  padding: 2rem 1rem 3rem;
  max-width: 640px;
  margin: 0 auto;
}

.page-title {
  font-family: 'Cinzel', serif;
  font-size: clamp(1.75rem, 4vw, 2.25rem);
  color: var(--dnd-ink);
  margin: 0 0 0.5rem;
}

.page-desc {
  color: var(--dnd-muted);
  font-size: 0.95rem;
  margin: 0 0 2rem;
}

.section-heading {
  font-family: 'Cinzel', serif;
  font-size: 1.1rem;
  color: var(--dnd-ink);
  margin: 0 0 0.75rem;
}

.add-section {
  margin-bottom: 2rem;
  padding: 1.25rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
}

.add-form {
  display: grid;
  grid-template-columns: 1fr 1fr auto;
  gap: 0.75rem;
  align-items: center;
}

.input {
  padding: 0.5rem 0.75rem;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.12);
  background: var(--dnd-bg);
  color: var(--dnd-ink);
  font-size: 1rem;
}
.input-url {
  font-family: ui-monospace, monospace;
  font-size: 0.9rem;
}

.btn {
  padding: 0.5rem 1rem;
  border-radius: 8px;
  border: none;
  font-weight: 600;
  cursor: pointer;
  background: var(--dnd-accent-2);
  color: var(--dnd-on-accent);
}
.btn.primary {
  background: var(--dnd-accent);
}
.btn.secondary {
  background: transparent;
  color: var(--dnd-muted);
  border: 1px solid currentColor;
}

.list-section {
  padding: 1.25rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
}

.empty {
  color: var(--dnd-muted);
  padding: 1.5rem;
  text-align: center;
  font-size: 0.95rem;
}

.link-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.link-item {
  display: flex;
  align-items: stretch;
  gap: 0.75rem;
}

.link-card {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  padding: 1rem 1.25rem;
  border-radius: 10px;
  border: 1px solid rgba(0, 0, 0, 0.08);
  background: rgba(0, 0, 0, 0.02);
  color: inherit;
  text-decoration: none;
  transition: background 0.15s, border-color 0.15s;
}
.link-card:hover {
  background: rgba(0, 0, 0, 0.05);
  border-color: var(--dnd-accent);
}

.link-label {
  font-weight: 700;
  font-size: 1rem;
  color: var(--dnd-ink);
}

.link-url {
  font-size: 0.8rem;
  color: var(--dnd-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.item-actions {
  display: flex;
  gap: 0.25rem;
  align-items: center;
}

.btn-icon {
  padding: 0.4rem 0.6rem;
  border: none;
  border-radius: 6px;
  background: transparent;
  color: var(--dnd-muted);
  font-size: 0.8rem;
  cursor: pointer;
}
.btn-icon:hover {
  background: rgba(0, 0, 0, 0.06);
  color: var(--dnd-ink);
}
.btn-icon.danger:hover {
  background: rgba(179, 58, 42, 0.15);
  color: #b33a2a;
}

.edit-form {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr 1fr auto;
  gap: 0.5rem;
  align-items: center;
}
.edit-actions {
  display: flex;
  gap: 0.5rem;
}

@media (max-width: 600px) {
  .add-form,
  .edit-form {
    grid-template-columns: 1fr;
  }
  .link-item {
    flex-direction: column;
  }
  .edit-form {
    grid-template-columns: 1fr;
  }
}
</style>
