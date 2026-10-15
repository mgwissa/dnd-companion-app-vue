<script setup lang="ts">
import { ref, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useCampaignStore } from '@/stores/campaign'
import { parseSessionPack, sessionBody, sessionSections, type SessionPack } from '@/lib/sessionImport'

const emit = defineEmits<{ imported: [noteId: string] }>()
const campaign = useCampaignStore()
const pack = ref<SessionPack | null>(null)
const selectedThreads = ref<boolean[]>([])
const shared = ref(false)
const busy = ref(false)
const error = ref('')
const fileInput = ref<HTMLInputElement | null>(null)

function reset() {
  pack.value = null
  error.value = ''
  selectedThreads.value = []
  shared.value = false
}

watch(() => campaign.activeCampaignId, reset)

async function readFile(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  reset()
  const campaignId = campaign.activeCampaignId
  try {
    if (file.size > 5 * 1024 * 1024) throw new Error('Choose a session file smaller than 5 MB.')
    const contents = await file.text()
    if (campaign.activeCampaignId !== campaignId) return
    pack.value = parseSessionPack(JSON.parse(contents))
    selectedThreads.value = pack.value.threads.map(() => false)
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Could not read this session file.'
  } finally {
    input.value = ''
  }
}

async function save() {
  if (!pack.value || !campaign.activeCampaignId || busy.value) return
  error.value = ''
  const campaignId = campaign.activeCampaignId
  try {
    const selected = pack.value.threads.filter((_, i) => selectedThreads.value[i]).map(t => t.trim()).filter(Boolean)
    const reviewed = parseSessionPack({ ...pack.value, playedOn: pack.value.playedOn || null })
    busy.value = true
    const { data, error: failure } = await supabase.rpc('import_session_pack', {
      p_campaign_id: campaignId,
      p_pack: { ...reviewed, body: sessionBody(reviewed), selectedThreads: selected },
      p_shared: shared.value,
    })
    if (failure) {
      if (failure.code === '23505') throw new Error('This session has already been imported into this campaign. Open the existing note to edit it.')
      if (failure.code === 'PGRST202') throw new Error('Session import is not installed yet. Apply database migration 012_session_import.sql first.')
      throw new Error(failure.message)
    }
    if (campaign.activeCampaignId === campaignId) {
      reset()
      emit('imported', data as string)
    }
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Could not import session. Nothing was saved.'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section class="session-import" aria-labelledby="session-import-heading">
    <div class="import-heading">
      <div>
        <h2 id="session-import-heading">Import session</h2>
        <p>Bring in a prepared session JSON file, review it, then save to {{ campaign.activeCampaign?.name ?? 'your campaign' }}.</p>
      </div>
      <button type="button" :disabled="busy || !campaign.activeCampaignId" @click="fileInput?.click()">Choose session file</button>
      <input ref="fileInput" class="visually-hidden" type="file" accept=".json,application/json" aria-label="Choose session JSON file" :disabled="busy" @change="readFile" />
    </div>
    <p v-if="error" role="alert">{{ error }}</p>
    <form v-if="pack" @submit.prevent="save">
      <fieldset :disabled="busy">
        <legend>Review session</legend>
        <label>Title<input v-model="pack.title" required /></label>
        <label>Played date (leave blank if unknown)<input v-model="pack.playedOn" type="date" /></label>
        <label>Where we left off<textarea v-model="pack.resumePoint" rows="6" required /></label>
        <label v-for="[key, label] in sessionSections" :key="key">{{ label }}<textarea v-model="pack[key]" :rows="key === 'recap' ? 10 : 4" :required="key === 'recap'" /></label>
        <h3>Suggested open threads</h3>
        <p>Choose which to add to the campaign’s shared thread list. All suggestions also stay in the session note.</p>
        <div v-for="(_, index) in pack.threads" :key="index" class="thread-choice">
          <input v-model="selectedThreads[index]" type="checkbox" :aria-label="`Add thread ${index + 1} to campaign`" />
          <input v-model="pack.threads[index]" :aria-label="`Thread ${index + 1}`" />
        </div>
        <label class="share-choice"><input v-model="shared" type="checkbox" /> Share reviewed session with the campaign</label>
        <p>The original transcript is saved as a separate private note. HP, inventory, and character conditions are not changed.</p>
        <details v-if="pack.transcript"><summary>Original transcript (private)</summary><pre>{{ pack.transcript }}</pre></details>
        <div class="import-actions">
          <button type="submit">{{ busy ? 'Saving…' : 'Save session' }}</button>
          <button type="button" @click="reset">Cancel</button>
        </div>
      </fieldset>
    </form>
  </section>
</template>

<style scoped>
.session-import { padding: 1.5rem; background: var(--dnd-elevated); color: var(--dnd-ink); border: 1px solid var(--dnd-muted); border-radius: 12px; }
.import-heading, .import-actions, .thread-choice { display: flex; gap: 1rem; align-items: center; flex-wrap: wrap; }
.import-heading > div { flex: 1; min-width: 12rem; }
h2, h3 { font-family: 'Spectral', serif; }
p { color: var(--dnd-muted); line-height: 1.5; }
fieldset { border: 0; padding: 1rem 0 0; margin: 0; min-width: 0; }
legend { font-weight: 600; }
label { display: block; margin: 1rem 0; }
input:not([type=checkbox]):not([type=file]), textarea { display: block; width: 100%; box-sizing: border-box; margin-top: .4rem; padding: .65rem; background: var(--dnd-input-bg); color: var(--dnd-ink); border: 1px solid var(--dnd-muted); border-radius: 6px; font: inherit; }
textarea { resize: vertical; line-height: 1.5; }
.thread-choice { flex-wrap: nowrap; margin: .5rem 0; }
.thread-choice input[type=checkbox] { flex-shrink: 0; }
.share-choice { display: flex; gap: .5rem; align-items: center; }
button { border: 1px solid var(--dnd-muted); border-radius: 6px; padding: .65rem 1rem; background: var(--dnd-input-bg); color: var(--dnd-ink); cursor: pointer; font: inherit; }
button[type=submit] { background: var(--dnd-accent); color: var(--dnd-on-accent); }
button:disabled { opacity: .6; cursor: wait; }
pre { max-height: 20rem; overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere; }
.import-actions { margin-top: 1rem; }
:focus-visible { outline: 2px solid var(--dnd-accent-2); outline-offset: 3px; }
</style>
