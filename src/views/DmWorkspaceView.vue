<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'
import { showToast } from '@/composables/useToast'

type RunStatus = 'prep' | 'running' | 'completed'
type SceneStatus = 'planned' | 'current' | 'completed'
type CombatantKind = 'pc' | 'enemy' | 'ally'

interface DmRun {
  id: string
  campaign_id: string
  created_by: string
  title: string
  planned_minutes: number
  status: RunStatus
  started_at: string | null
  ended_at: string | null
  log_note_id: string | null
  created_at: string
  updated_at: string
}

interface DmScene {
  id: string
  run_id: string
  campaign_id: string
  created_by: string
  title: string
  purpose: string
  read_aloud: string
  secrets: string
  notes: string
  estimated_minutes: number
  sort_order: number
  status: SceneStatus
  created_at: string
  updated_at: string
}

interface DmEncounter {
  id: string
  run_id: string
  scene_id: string | null
  campaign_id: string
  created_by: string
  title: string
  is_active: boolean
  round: number
  turn_index: number
  created_at: string
  updated_at: string
}

interface DmCombatant {
  id: string
  encounter_id: string
  campaign_id: string
  source_character_id: string | null
  name: string
  kind: CombatantKind
  initiative: number | null
  armor_class: number | null
  max_hp: number
  current_hp: number
  temp_hp: number
  conditions: string[]
  sort_order: number
  created_at: string
  updated_at: string
}

interface PartyCharacter {
  id: string
  character_name: string
  avatar_url: string
  max_hp: number
  current_hp: number
  temp_hp: number
}

interface ContentPackCombatant {
  name: string
  kind: CombatantKind
  initiative?: number | null
  armorClass?: number | null
  maxHp: number
  currentHp?: number
  tempHp?: number
  conditions?: string[]
}

interface ContentPackScene {
  key: string
  title: string
  estimatedMinutes: number
  purpose: string
  readAloud: string
  secrets: string
  notes: string
}

interface ContentPackEncounter {
  title: string
  sceneKey: string
  combatants: ContentPackCombatant[]
}

interface DmContentPack {
  version: 1
  run: {
    title: string
    plannedMinutes: number
    overview: string
  }
  scenes: ContentPackScene[]
  encounters: ContentPackEncounter[]
}

const auth = useAuthStore()
const campaignStore = useCampaignStore()

const loading = ref(true)
const saving = ref(false)
const schemaMissing = ref(false)
const mode = ref<'prep' | 'run'>('prep')
const run = ref<DmRun | null>(null)
const scenes = ref<DmScene[]>([])
const encounters = ref<DmEncounter[]>([])
const combatants = ref<DmCombatant[]>([])
const party = ref<PartyCharacter[]>([])
const selectedSceneId = ref<string | null>(null)
const selectedEncounterId = ref<string | null>(null)
const now = ref(Date.now())
let timer: ReturnType<typeof setInterval> | null = null

const setupTitle = ref('')
const setupMinutes = ref(240)
const sceneEditingId = ref<string | null>(null)
const sceneForm = ref({
  title: '',
  purpose: '',
  read_aloud: '',
  secrets: '',
  notes: '',
  estimated_minutes: 20,
})
const encounterTitle = ref('')
const encounterSceneId = ref('')
const combatantForm = ref({
  name: '',
  kind: 'enemy' as CombatantKind,
  initiative: '',
  armor_class: '',
  max_hp: 10,
})
const hpAmounts = ref<Record<string, number>>({})
const conditionDrafts = ref<Record<string, string>>({})
const captureType = ref('Discovery')
const captureText = ref('')
const importDialogOpen = ref(false)
const importText = ref('')
const importPack = ref<DmContentPack | null>(null)
const importSourceName = ref('')
const importError = ref('')
const importing = ref(false)
const loadingStarterPack = ref(false)
const exporting = ref(false)

const campaignId = computed(() => campaignStore.activeCampaignId)
const campaignName = computed(() => campaignStore.activeCampaign?.name ?? 'Campaign')
const isDm = computed(() =>
  Boolean(auth.user && campaignStore.activeCampaign?.created_by === auth.user.id),
)
const orderedScenes = computed(() =>
  [...scenes.value].sort(
    (a, b) => a.sort_order - b.sort_order || a.created_at.localeCompare(b.created_at),
  ),
)
const currentScene = computed(
  () => orderedScenes.value.find((scene) => scene.status === 'current') ?? null,
)
const selectedScene = computed(
  () => scenes.value.find((scene) => scene.id === selectedSceneId.value) ?? currentScene.value,
)
const nextScene = computed(() => {
  const currentIndex = orderedScenes.value.findIndex((scene) => scene.id === currentScene.value?.id)
  return (
    orderedScenes.value.slice(currentIndex + 1).find((scene) => scene.status !== 'completed') ??
    null
  )
})
const selectedEncounter = computed(
  () => encounters.value.find((encounter) => encounter.id === selectedEncounterId.value) ?? null,
)
const encounterCombatants = computed(() => {
  if (!selectedEncounterId.value) return []
  return combatants.value
    .filter((combatant) => combatant.encounter_id === selectedEncounterId.value)
    .sort((a, b) => {
      if (a.initiative === null && b.initiative !== null) return 1
      if (a.initiative !== null && b.initiative === null) return -1
      if (a.initiative !== b.initiative) return (b.initiative ?? 0) - (a.initiative ?? 0)
      return a.sort_order - b.sort_order || a.created_at.localeCompare(b.created_at)
    })
})
const activeCombatant = computed(() => {
  if (!selectedEncounter.value?.is_active || encounterCombatants.value.length === 0) return null
  return encounterCombatants.value[
    selectedEncounter.value.turn_index % encounterCombatants.value.length
  ]
})
const elapsedMilliseconds = computed(() => {
  if (!run.value?.started_at) return 0
  const end = run.value.ended_at ? new Date(run.value.ended_at).getTime() : now.value
  return Math.max(0, end - new Date(run.value.started_at).getTime())
})
const elapsedMinutes = computed(() => Math.floor(elapsedMilliseconds.value / 60_000))
const clockLabel = computed(() => {
  const totalSeconds = Math.floor(elapsedMilliseconds.value / 1000)
  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
})
const pacePercent = computed(() => {
  if (!run.value?.planned_minutes) return 0
  return Math.min(100, (elapsedMinutes.value / run.value.planned_minutes) * 100)
})
const currentSceneTarget = computed(() => {
  if (!currentScene.value) return 0
  const currentIndex = orderedScenes.value.findIndex((scene) => scene.id === currentScene.value?.id)
  return orderedScenes.value
    .slice(0, currentIndex + 1)
    .reduce((total, scene) => total + scene.estimated_minutes, 0)
})
const paceMessage = computed(() => {
  if (!run.value?.started_at) return 'Clock starts when you begin the one-shot.'
  if (!currentScene.value)
    return `${Math.max(0, run.value.planned_minutes - elapsedMinutes.value)} minutes remain.`
  const delta = currentSceneTarget.value - elapsedMinutes.value
  if (delta >= 0) return `${delta} min of breathing room before this scene's target.`
  return `${Math.abs(delta)} min past this scene's target—consider trimming the next beat.`
})
const completedSceneCount = computed(
  () => scenes.value.filter((scene) => scene.status === 'completed').length,
)
const importSceneMinutes = computed(
  () => importPack.value?.scenes.reduce((total, scene) => total + scene.estimatedMinutes, 0) ?? 0,
)

function isMissingTableError(error: { code?: string; message?: string } | null) {
  return error?.code === '42P01' || Boolean(error?.message?.includes('dm_runs'))
}

function setTimer() {
  if (timer) clearInterval(timer)
  timer = setInterval(() => {
    now.value = Date.now()
  }, 1000)
}

async function initialize() {
  if (!campaignId.value) return
  loading.value = true
  schemaMissing.value = false
  run.value = null
  scenes.value = []
  encounters.value = []
  combatants.value = []
  try {
    if (campaignStore.campaigns.length === 0) await campaignStore.fetchCampaigns()
    await campaignStore.fetchMembers(campaignId.value)
    if (!isDm.value) return

    setupTitle.value = `${campaignName.value} one-shot`
    const { data, error } = await supabase
      .from('dm_runs')
      .select('*')
      .eq('campaign_id', campaignId.value)
      .in('status', ['prep', 'running'])
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()
    if (error) {
      if (isMissingTableError(error)) {
        schemaMissing.value = true
        return
      }
      throw error
    }
    run.value = (data as DmRun | null) ?? null
    if (run.value) {
      setupTitle.value = run.value.title
      setupMinutes.value = run.value.planned_minutes
      mode.value = run.value.status === 'running' ? 'run' : 'prep'
      await loadWorkspaceData()
    }
  } catch (error) {
    console.warn('Failed to load DM workspace', error)
    showToast('Failed to load the DM workspace', 'error')
  } finally {
    loading.value = false
  }
}

async function loadWorkspaceData() {
  if (!run.value || !campaignId.value) return
  const [sceneResult, encounterResult, partyResult] = await Promise.all([
    supabase.from('dm_scenes').select('*').eq('run_id', run.value.id).order('sort_order'),
    supabase.from('dm_encounters').select('*').eq('run_id', run.value.id).order('created_at'),
    supabase
      .from('characters')
      .select('id, character_name, avatar_url, max_hp, current_hp, temp_hp')
      .eq('campaign_id', campaignId.value)
      .eq('is_active', true)
      .eq('is_npc', false)
      .order('character_name'),
  ])
  if (sceneResult.error) throw sceneResult.error
  if (encounterResult.error) throw encounterResult.error
  if (partyResult.error) throw partyResult.error
  scenes.value = (sceneResult.data ?? []) as DmScene[]
  encounters.value = (encounterResult.data ?? []) as DmEncounter[]
  party.value = (partyResult.data ?? []) as PartyCharacter[]
  selectedSceneId.value = currentScene.value?.id ?? orderedScenes.value[0]?.id ?? null
  selectedEncounterId.value =
    encounters.value.find((encounter) => encounter.is_active)?.id ?? encounters.value[0]?.id ?? null

  const encounterIds = encounters.value.map((encounter) => encounter.id)
  if (encounterIds.length > 0) {
    const { data, error } = await supabase
      .from('dm_combatants')
      .select('*')
      .in('encounter_id', encounterIds)
    if (error) throw error
    combatants.value = (data ?? []) as DmCombatant[]
    conditionDrafts.value = Object.fromEntries(
      combatants.value.map((combatant) => [combatant.id, combatant.conditions.join(', ')]),
    )
  } else {
    combatants.value = []
  }
}

async function createRun() {
  if (!campaignId.value || !auth.user) return
  const title = setupTitle.value.trim()
  if (!title) {
    showToast('Give the run sheet a title', 'error')
    return
  }
  saving.value = true
  try {
    const { data, error } = await supabase
      .from('dm_runs')
      .insert({
        campaign_id: campaignId.value,
        created_by: auth.user.id,
        title,
        planned_minutes: Math.max(15, setupMinutes.value || 240),
      })
      .select()
      .single()
    if (error) throw error
    run.value = data as DmRun
    mode.value = 'prep'
    showToast('Run sheet ready', 'success')
  } catch (error) {
    console.warn('Failed to create run sheet', error)
    showToast('Failed to create the run sheet', 'error')
  } finally {
    saving.value = false
  }
}

async function saveRunSettings() {
  if (!run.value) return
  const title = setupTitle.value.trim()
  if (!title) return
  const minutes = Math.max(15, setupMinutes.value || 240)
  const { error } = await supabase
    .from('dm_runs')
    .update({ title, planned_minutes: minutes, updated_at: new Date().toISOString() })
    .eq('id', run.value.id)
  if (error) {
    showToast('Failed to save run settings', 'error')
    return
  }
  run.value.title = title
  run.value.planned_minutes = minutes
  showToast('Run settings saved', 'success')
}

async function ensureLogNote() {
  if (!run.value || !campaignId.value || !auth.user) return null
  if (run.value.log_note_id) return run.value.log_note_id
  const { data, error } = await supabase
    .from('notes')
    .insert({
      user_id: auth.user.id,
      campaign_id: campaignId.value,
      title: `${run.value.title} — DM log`,
      body: `# ${run.value.title}\n\nPrivate DM session log.\n`,
      tags: ['dm-log'],
      is_shared: false,
      updated_at: new Date().toISOString(),
    })
    .select('id')
    .single()
  if (error) throw error
  const noteId = data.id as string
  const { error: updateError } = await supabase
    .from('dm_runs')
    .update({ log_note_id: noteId, updated_at: new Date().toISOString() })
    .eq('id', run.value.id)
  if (updateError) throw updateError
  run.value.log_note_id = noteId
  return noteId
}

async function startRun() {
  if (!run.value || scenes.value.length === 0) {
    showToast('Add at least one scene before starting', 'error')
    return
  }
  saving.value = true
  try {
    await ensureLogNote()
    const startedAt = run.value.started_at ?? new Date().toISOString()
    const { error } = await supabase
      .from('dm_runs')
      .update({
        status: 'running',
        started_at: startedAt,
        ended_at: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', run.value.id)
    if (error) throw error
    run.value.status = 'running'
    run.value.started_at = startedAt
    run.value.ended_at = null
    if (!currentScene.value) await makeSceneCurrent(orderedScenes.value[0])
    mode.value = 'run'
    showToast('The one-shot is live', 'success')
  } catch (error) {
    console.warn('Failed to start run', error)
    showToast('Failed to start the one-shot', 'error')
  } finally {
    saving.value = false
  }
}

async function resetClock() {
  if (!run.value || !window.confirm('Reset the live session clock to zero?')) return
  const startedAt = new Date().toISOString()
  const { error } = await supabase
    .from('dm_runs')
    .update({ started_at: startedAt })
    .eq('id', run.value.id)
  if (error) return showToast('Failed to reset the clock', 'error')
  run.value.started_at = startedAt
  now.value = Date.now()
}

async function completeRun() {
  if (!run.value || !window.confirm('End this one-shot and close the active run sheet?')) return
  const endedAt = new Date().toISOString()
  const { error } = await supabase
    .from('dm_runs')
    .update({ status: 'completed', ended_at: endedAt, updated_at: endedAt })
    .eq('id', run.value.id)
  if (error) return showToast('Failed to end the one-shot', 'error')
  run.value.status = 'completed'
  run.value.ended_at = endedAt
  showToast('One-shot complete. Nice work, DM.', 'success')
}

function planAnotherRun() {
  run.value = null
  scenes.value = []
  encounters.value = []
  combatants.value = []
  selectedSceneId.value = null
  selectedEncounterId.value = null
  setupTitle.value = `${campaignName.value} one-shot`
  setupMinutes.value = 240
  mode.value = 'prep'
}

function resetSceneForm() {
  sceneEditingId.value = null
  sceneForm.value = {
    title: '',
    purpose: '',
    read_aloud: '',
    secrets: '',
    notes: '',
    estimated_minutes: 20,
  }
}

function editScene(scene: DmScene) {
  sceneEditingId.value = scene.id
  selectedSceneId.value = scene.id
  sceneForm.value = {
    title: scene.title,
    purpose: scene.purpose,
    read_aloud: scene.read_aloud,
    secrets: scene.secrets,
    notes: scene.notes,
    estimated_minutes: scene.estimated_minutes,
  }
}

function editSceneInPrep(scene: DmScene) {
  editScene(scene)
  mode.value = 'prep'
}

async function saveScene() {
  if (!run.value || !campaignId.value || !auth.user) return
  const title = sceneForm.value.title.trim()
  if (!title) return showToast('Give the scene a title', 'error')
  saving.value = true
  const payload = {
    title,
    purpose: sceneForm.value.purpose.trim(),
    read_aloud: sceneForm.value.read_aloud.trim(),
    secrets: sceneForm.value.secrets.trim(),
    notes: sceneForm.value.notes.trim(),
    estimated_minutes: Math.max(0, sceneForm.value.estimated_minutes || 0),
    updated_at: new Date().toISOString(),
  }
  try {
    if (sceneEditingId.value) {
      const { data, error } = await supabase
        .from('dm_scenes')
        .update(payload)
        .eq('id', sceneEditingId.value)
        .select()
        .single()
      if (error) throw error
      const index = scenes.value.findIndex((scene) => scene.id === sceneEditingId.value)
      if (index !== -1) scenes.value[index] = data as DmScene
      showToast('Scene updated', 'success')
    } else {
      const sortOrder = orderedScenes.value.length
        ? Math.max(...orderedScenes.value.map((scene) => scene.sort_order)) + 1
        : 0
      const { data, error } = await supabase
        .from('dm_scenes')
        .insert({
          ...payload,
          run_id: run.value.id,
          campaign_id: campaignId.value,
          created_by: auth.user.id,
          sort_order: sortOrder,
        })
        .select()
        .single()
      if (error) throw error
      scenes.value.push(data as DmScene)
      selectedSceneId.value = data.id
      showToast('Scene added to the run sheet', 'success')
    }
    resetSceneForm()
  } catch (error) {
    console.warn('Failed to save scene', error)
    showToast('Failed to save the scene', 'error')
  } finally {
    saving.value = false
  }
}

async function deleteScene(scene: DmScene) {
  if (!window.confirm(`Delete “${scene.title}” from the run sheet?`)) return
  const { error } = await supabase.from('dm_scenes').delete().eq('id', scene.id)
  if (error) return showToast('Failed to delete the scene', 'error')
  scenes.value = scenes.value.filter((item) => item.id !== scene.id)
  if (selectedSceneId.value === scene.id) selectedSceneId.value = orderedScenes.value[0]?.id ?? null
  if (sceneEditingId.value === scene.id) resetSceneForm()
}

async function moveScene(scene: DmScene, direction: -1 | 1) {
  const list = orderedScenes.value
  const index = list.findIndex((item) => item.id === scene.id)
  const other = list[index + direction]
  if (!other) return
  const firstOrder = scene.sort_order
  const secondOrder = other.sort_order
  const [first, second] = await Promise.all([
    supabase.from('dm_scenes').update({ sort_order: secondOrder }).eq('id', scene.id),
    supabase.from('dm_scenes').update({ sort_order: firstOrder }).eq('id', other.id),
  ])
  if (first.error || second.error) return showToast('Failed to reorder scenes', 'error')
  scene.sort_order = secondOrder
  other.sort_order = firstOrder
}

async function makeSceneCurrent(scene: DmScene) {
  const previous = scenes.value.find((item) => item.status === 'current' && item.id !== scene.id)
  if (previous) {
    const { error } = await supabase
      .from('dm_scenes')
      .update({ status: 'planned' })
      .eq('id', previous.id)
    if (error) return showToast('Failed to change scenes', 'error')
    previous.status = 'planned'
  }
  const { error } = await supabase
    .from('dm_scenes')
    .update({ status: 'current', updated_at: new Date().toISOString() })
    .eq('id', scene.id)
  if (error) return showToast('Failed to change scenes', 'error')
  scene.status = 'current'
  selectedSceneId.value = scene.id
}

async function advanceScene() {
  const current = currentScene.value
  if (!current) {
    const first = orderedScenes.value.find((scene) => scene.status !== 'completed')
    if (first) await makeSceneCurrent(first)
    return
  }
  const next = nextScene.value
  const { error } = await supabase
    .from('dm_scenes')
    .update({ status: 'completed', updated_at: new Date().toISOString() })
    .eq('id', current.id)
  if (error) return showToast('Failed to complete the scene', 'error')
  current.status = 'completed'
  if (next) {
    await makeSceneCurrent(next)
    showToast(`Now running: ${next.title}`, 'success')
  } else {
    selectedSceneId.value = current.id
    showToast('Every scene is complete', 'success')
  }
}

async function copyReadAloud() {
  if (!currentScene.value?.read_aloud) return
  try {
    await navigator.clipboard.writeText(currentScene.value.read_aloud)
    showToast('Read-aloud text copied', 'success')
  } catch {
    showToast('Could not copy read-aloud text', 'error')
  }
}

async function addCapture() {
  const text = captureText.value.trim()
  if (!text || !run.value) return
  try {
    const noteId = await ensureLogNote()
    if (!noteId) return
    const { data, error } = await supabase.from('notes').select('body').eq('id', noteId).single()
    if (error) throw error
    const time = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(
      new Date(),
    )
    const sceneLabel = currentScene.value ? ` · ${currentScene.value.title}` : ''
    const body = `${(data.body as string).trimEnd()}\n\n## ${time} — ${captureType.value}${sceneLabel}\n${text}\n`
    const { error: updateError } = await supabase
      .from('notes')
      .update({ body, updated_at: new Date().toISOString() })
      .eq('id', noteId)
    if (updateError) throw updateError

    if (captureType.value === 'Campaign thread' && campaignId.value && auth.user) {
      const { error: threadError } = await supabase.from('campaign_threads').insert({
        campaign_id: campaignId.value,
        created_by: auth.user.id,
        title: text,
      })
      if (threadError) showToast('DM log saved, but the shared thread failed', 'error')
    } else {
      showToast(`${captureType.value} captured`, 'success')
    }
    captureText.value = ''
  } catch (error) {
    console.warn('Failed to add DM capture', error)
    showToast('Failed to save the capture', 'error')
  }
}

async function createEncounter() {
  if (!run.value || !campaignId.value || !auth.user) return
  const title = encounterTitle.value.trim()
  if (!title) return showToast('Give the encounter a title', 'error')
  const { data, error } = await supabase
    .from('dm_encounters')
    .insert({
      run_id: run.value.id,
      campaign_id: campaignId.value,
      created_by: auth.user.id,
      title,
      scene_id: encounterSceneId.value || null,
    })
    .select()
    .single()
  if (error) return showToast('Failed to create the encounter', 'error')
  encounters.value.push(data as DmEncounter)
  selectedEncounterId.value = data.id
  encounterTitle.value = ''
  encounterSceneId.value = ''
  showToast('Encounter ready', 'success')
}

async function deleteEncounter(encounter: DmEncounter) {
  if (!window.confirm(`Delete “${encounter.title}” and its combatants?`)) return
  const { error } = await supabase.from('dm_encounters').delete().eq('id', encounter.id)
  if (error) return showToast('Failed to delete the encounter', 'error')
  encounters.value = encounters.value.filter((item) => item.id !== encounter.id)
  combatants.value = combatants.value.filter((item) => item.encounter_id !== encounter.id)
  selectedEncounterId.value = encounters.value[0]?.id ?? null
}

async function addPartyToEncounter() {
  if (!selectedEncounter.value || !campaignId.value) return
  const existingIds = new Set(
    encounterCombatants.value.map((combatant) => combatant.source_character_id).filter(Boolean),
  )
  const additions = party.value.filter((character) => !existingIds.has(character.id))
  if (additions.length === 0)
    return showToast('The whole party is already in this encounter', 'info')
  const nextOrder = encounterCombatants.value.length
  const rows = additions.map((character, index) => ({
    encounter_id: selectedEncounter.value!.id,
    campaign_id: campaignId.value,
    source_character_id: character.id,
    name: character.character_name,
    kind: 'pc' as const,
    max_hp: Math.max(0, character.max_hp),
    current_hp: Math.max(0, character.current_hp),
    temp_hp: Math.max(0, character.temp_hp),
    sort_order: nextOrder + index,
  }))
  const { data, error } = await supabase.from('dm_combatants').insert(rows).select()
  if (error) return showToast('Failed to add the party', 'error')
  combatants.value.push(...((data ?? []) as DmCombatant[]))
  showToast(`${additions.length} party members added`, 'success')
}

async function addCombatant() {
  if (!selectedEncounter.value || !campaignId.value) return
  const name = combatantForm.value.name.trim()
  if (!name) return showToast('Give the combatant a name', 'error')
  const maxHp = Math.max(0, Number(combatantForm.value.max_hp) || 0)
  const { data, error } = await supabase
    .from('dm_combatants')
    .insert({
      encounter_id: selectedEncounter.value.id,
      campaign_id: campaignId.value,
      name,
      kind: combatantForm.value.kind,
      initiative:
        combatantForm.value.initiative === '' ? null : Number(combatantForm.value.initiative),
      armor_class:
        combatantForm.value.armor_class === '' ? null : Number(combatantForm.value.armor_class),
      max_hp: maxHp,
      current_hp: maxHp,
      sort_order: encounterCombatants.value.length,
    })
    .select()
    .single()
  if (error) return showToast('Failed to add the combatant', 'error')
  combatants.value.push(data as DmCombatant)
  conditionDrafts.value[data.id] = ''
  combatantForm.value = { name: '', kind: 'enemy', initiative: '', armor_class: '', max_hp: 10 }
}

async function duplicateCombatant(combatant: DmCombatant) {
  if (!campaignId.value) return
  const { data, error } = await supabase
    .from('dm_combatants')
    .insert({
      encounter_id: combatant.encounter_id,
      campaign_id: campaignId.value,
      name: combatant.name,
      kind: combatant.kind,
      initiative: combatant.initiative,
      armor_class: combatant.armor_class,
      max_hp: combatant.max_hp,
      current_hp: combatant.max_hp,
      conditions: [],
      sort_order: encounterCombatants.value.length,
    })
    .select()
    .single()
  if (error) return showToast('Failed to duplicate the combatant', 'error')
  combatants.value.push(data as DmCombatant)
  conditionDrafts.value[data.id] = ''
}

async function removeCombatant(combatant: DmCombatant) {
  const { error } = await supabase.from('dm_combatants').delete().eq('id', combatant.id)
  if (error) return showToast('Failed to remove the combatant', 'error')
  combatants.value = combatants.value.filter((item) => item.id !== combatant.id)
}

async function patchCombatant(combatant: DmCombatant, patch: Partial<DmCombatant>) {
  const { error } = await supabase
    .from('dm_combatants')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('id', combatant.id)
  if (error) {
    showToast('Failed to update the combatant', 'error')
    return false
  }
  Object.assign(combatant, patch)
  return true
}

async function saveCombatantNumber(
  combatant: DmCombatant,
  field: 'initiative' | 'armor_class',
  event: Event,
) {
  const raw = (event.target as HTMLInputElement).value
  await patchCombatant(combatant, { [field]: raw === '' ? null : Number(raw) })
}

async function saveConditions(combatant: DmCombatant) {
  const conditions = (conditionDrafts.value[combatant.id] ?? '')
    .split(',')
    .map((condition) => condition.trim())
    .filter(Boolean)
  await patchCombatant(combatant, { conditions })
}

async function applyHp(combatant: DmCombatant, direction: 'damage' | 'heal') {
  const amount = Math.max(0, hpAmounts.value[combatant.id] || 0)
  if (!amount) return
  let currentHp = combatant.current_hp
  let tempHp = combatant.temp_hp
  if (direction === 'heal') {
    currentHp = Math.min(combatant.max_hp, currentHp + amount)
  } else {
    const absorbed = Math.min(tempHp, amount)
    tempHp -= absorbed
    currentHp = Math.max(0, currentHp - (amount - absorbed))
  }
  const saved = await patchCombatant(combatant, { current_hp: currentHp, temp_hp: tempHp })
  if (!saved) return
  hpAmounts.value[combatant.id] = 0
  if (combatant.source_character_id) {
    const { error } = await supabase.rpc('update_character_hp', {
      p_character_id: combatant.source_character_id,
      p_current_hp: currentHp,
      p_temp_hp: tempHp,
    })
    if (error) showToast('Encounter HP saved, but party HP did not sync', 'error')
    const partyCharacter = party.value.find(
      (character) => character.id === combatant.source_character_id,
    )
    if (partyCharacter) {
      partyCharacter.current_hp = currentHp
      partyCharacter.temp_hp = tempHp
    }
  }
}

async function startEncounter(encounter: DmEncounter) {
  if (encounters.value.some((item) => item.is_active && item.id !== encounter.id)) {
    const { error } = await supabase
      .from('dm_encounters')
      .update({ is_active: false })
      .eq('run_id', encounter.run_id)
      .neq('id', encounter.id)
    if (error) return showToast('Failed to switch encounters', 'error')
    encounters.value.forEach((item) => {
      if (item.id !== encounter.id) item.is_active = false
    })
  }
  const { error } = await supabase
    .from('dm_encounters')
    .update({ is_active: true, round: 1, turn_index: 0, updated_at: new Date().toISOString() })
    .eq('id', encounter.id)
  if (error) return showToast('Failed to start the encounter', 'error')
  encounter.is_active = true
  encounter.round = 1
  encounter.turn_index = 0
  selectedEncounterId.value = encounter.id
}

async function endEncounter(encounter: DmEncounter) {
  const { error } = await supabase
    .from('dm_encounters')
    .update({ is_active: false })
    .eq('id', encounter.id)
  if (error) return showToast('Failed to end the encounter', 'error')
  encounter.is_active = false
  showToast('Encounter ended', 'success')
}

async function moveTurn(direction: -1 | 1) {
  const encounter = selectedEncounter.value
  const count = encounterCombatants.value.length
  if (!encounter || count === 0) return
  let turnIndex = encounter.turn_index + direction
  let round = encounter.round
  if (turnIndex >= count) {
    turnIndex = 0
    round += 1
  } else if (turnIndex < 0) {
    turnIndex = count - 1
    round = Math.max(1, round - 1)
  }
  const { error } = await supabase
    .from('dm_encounters')
    .update({ turn_index: turnIndex, round, updated_at: new Date().toISOString() })
    .eq('id', encounter.id)
  if (error) return showToast('Failed to advance initiative', 'error')
  encounter.turn_index = turnIndex
  encounter.round = round
}

async function jumpToTurn(combatant: DmCombatant) {
  const encounter = selectedEncounter.value
  if (!encounter?.is_active) return
  const turnIndex = encounterCombatants.value.findIndex((item) => item.id === combatant.id)
  if (turnIndex < 0) return
  const { error } = await supabase
    .from('dm_encounters')
    .update({ turn_index: turnIndex })
    .eq('id', encounter.id)
  if (error) return
  encounter.turn_index = turnIndex
}

function hpPercent(current: number, max: number) {
  if (max <= 0) return 0
  return Math.max(0, Math.min(100, (current / max) * 100))
}

function sceneForEncounter(encounter: DmEncounter) {
  return (
    scenes.value.find((scene) => scene.id === encounter.scene_id)?.title ?? 'Unlinked encounter'
  )
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function packString(record: Record<string, unknown>, key: string, fallback = '') {
  const value = record[key]
  return typeof value === 'string' ? value : fallback
}

function packNumber(record: Record<string, unknown>, key: string, fallback: number) {
  const value = record[key]
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function parseContentPack(value: unknown): DmContentPack {
  if (!isRecord(value)) throw new Error('The content pack must be a JSON object.')
  if (value.version !== 1) throw new Error('Only content pack version 1 is supported.')
  if (!isRecord(value.run)) throw new Error('The content pack is missing its run details.')
  if (!Array.isArray(value.scenes) || value.scenes.length === 0) {
    throw new Error('The content pack needs at least one scene.')
  }

  const title = packString(value.run, 'title').trim()
  if (!title) throw new Error('The run sheet needs a title.')
  const keys = new Set<string>()
  const scenes = value.scenes.map((rawScene, index): ContentPackScene => {
    if (!isRecord(rawScene)) throw new Error(`Scene ${index + 1} is not valid.`)
    const key = packString(rawScene, 'key').trim()
    const sceneTitle = packString(rawScene, 'title').trim()
    if (!key) throw new Error(`Scene ${index + 1} needs a stable key.`)
    if (keys.has(key)) throw new Error(`The scene key “${key}” is used more than once.`)
    if (!sceneTitle) throw new Error(`Scene ${index + 1} needs a title.`)
    keys.add(key)
    return {
      key,
      title: sceneTitle,
      estimatedMinutes: Math.max(0, Math.min(480, packNumber(rawScene, 'estimatedMinutes', 20))),
      purpose: packString(rawScene, 'purpose'),
      readAloud: packString(rawScene, 'readAloud'),
      secrets: packString(rawScene, 'secrets'),
      notes: packString(rawScene, 'notes'),
    }
  })

  const rawEncounters = value.encounters ?? []
  if (!Array.isArray(rawEncounters)) throw new Error('Encounters must be a JSON array.')
  const encounters = rawEncounters.map((rawEncounter, encounterIndex): ContentPackEncounter => {
    if (!isRecord(rawEncounter)) throw new Error(`Encounter ${encounterIndex + 1} is not valid.`)
    const encounterTitle = packString(rawEncounter, 'title').trim()
    const sceneKey = packString(rawEncounter, 'sceneKey').trim()
    if (!encounterTitle) throw new Error(`Encounter ${encounterIndex + 1} needs a title.`)
    if (sceneKey && !keys.has(sceneKey)) {
      throw new Error(`Encounter “${encounterTitle}” references the unknown scene “${sceneKey}”.`)
    }
    const rawCombatants = rawEncounter.combatants ?? []
    if (!Array.isArray(rawCombatants)) {
      throw new Error(`Combatants for “${encounterTitle}” must be a JSON array.`)
    }
    const parsedCombatants = rawCombatants.map(
      (rawCombatant, combatantIndex): ContentPackCombatant => {
        if (!isRecord(rawCombatant)) {
          throw new Error(`Combatant ${combatantIndex + 1} in “${encounterTitle}” is not valid.`)
        }
        const name = packString(rawCombatant, 'name').trim()
        if (!name) {
          throw new Error(`Combatant ${combatantIndex + 1} in “${encounterTitle}” needs a name.`)
        }
        const rawKind = packString(rawCombatant, 'kind', 'enemy')
        if (!['pc', 'enemy', 'ally'].includes(rawKind)) {
          throw new Error(`Combatant “${name}” has an unsupported kind.`)
        }
        const conditions = Array.isArray(rawCombatant.conditions)
          ? rawCombatant.conditions.filter(
              (condition): condition is string => typeof condition === 'string',
            )
          : []
        const maxHp = Math.max(0, packNumber(rawCombatant, 'maxHp', 1))
        return {
          name,
          kind: rawKind as CombatantKind,
          initiative: typeof rawCombatant.initiative === 'number' ? rawCombatant.initiative : null,
          armorClass:
            typeof rawCombatant.armorClass === 'number'
              ? Math.max(0, rawCombatant.armorClass)
              : null,
          maxHp,
          currentHp: Math.max(0, packNumber(rawCombatant, 'currentHp', maxHp)),
          tempHp: Math.max(0, packNumber(rawCombatant, 'tempHp', 0)),
          conditions,
        }
      },
    )
    return { title: encounterTitle, sceneKey, combatants: parsedCombatants }
  })

  return {
    version: 1,
    run: {
      title,
      plannedMinutes: Math.max(15, Math.min(720, packNumber(value.run, 'plannedMinutes', 180))),
      overview: packString(value.run, 'overview'),
    },
    scenes,
    encounters,
  }
}

function resetImporter() {
  importText.value = ''
  importPack.value = null
  importSourceName.value = ''
  importError.value = ''
}

function openImporter() {
  resetImporter()
  importDialogOpen.value = true
}

function closeImporter() {
  if (importing.value) return
  importDialogOpen.value = false
}

function previewImportText(sourceName = 'Pasted JSON') {
  importError.value = ''
  importPack.value = null
  try {
    importPack.value = parseContentPack(JSON.parse(importText.value) as unknown)
    importSourceName.value = sourceName
  } catch (error) {
    importError.value = error instanceof Error ? error.message : 'The JSON could not be read.'
  }
}

async function loadStarterPack() {
  importDialogOpen.value = true
  resetImporter()
  loadingStarterPack.value = true
  try {
    const response = await fetch(`${import.meta.env.BASE_URL}content-packs/road-to-candlekeep.json`)
    if (!response.ok) throw new Error('The bundled one-shot could not be loaded.')
    importText.value = await response.text()
    previewImportText('Bundled Candlekeep draft')
  } catch (error) {
    importError.value =
      error instanceof Error ? error.message : 'The starter pack could not be loaded.'
  } finally {
    loadingStarterPack.value = false
  }
}

async function onContentPackFile(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  importText.value = await file.text()
  previewImportText(file.name)
  input.value = ''
}

async function importContentPack() {
  if (!importPack.value || !campaignId.value) return
  importing.value = true
  importError.value = ''
  try {
    const { error } = await supabase.rpc('import_dm_run_pack', {
      p_campaign_id: campaignId.value,
      p_pack: importPack.value,
    })
    if (error) throw error
    importDialogOpen.value = false
    showToast(`Imported “${importPack.value.run.title}”`, 'success')
    await initialize()
  } catch (error) {
    console.warn('Failed to import content pack', error)
    const message =
      error instanceof Error
        ? error.message
        : isRecord(error) && typeof error.message === 'string'
          ? error.message
          : 'The content pack could not be imported.'
    importError.value = /import_dm_run_pack|schema cache/i.test(message)
      ? 'Apply migration 009_import_dm_run_pack.sql, then try again.'
      : message
  } finally {
    importing.value = false
  }
}

function contentPackFilename(title: string) {
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
  return `${slug || 'dm-run-sheet'}.json`
}

async function exportContentPack() {
  if (!run.value) return
  exporting.value = true
  try {
    let overview = 'Exported DM run sheet.'
    if (run.value.log_note_id) {
      const { data } = await supabase
        .from('notes')
        .select('body')
        .eq('id', run.value.log_note_id)
        .single()
      if (typeof data?.body === 'string') {
        overview = data.body.replace(/^# .*\r?\n+/, '').trim()
      }
    }

    const sceneKeys = new Map<string, string>()
    const packedScenes = orderedScenes.value.map((scene, index): ContentPackScene => {
      const slug = scene.title
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '')
      const key = `${slug || 'scene'}-${index + 1}`
      sceneKeys.set(scene.id, key)
      return {
        key,
        title: scene.title,
        estimatedMinutes: scene.estimated_minutes,
        purpose: scene.purpose,
        readAloud: scene.read_aloud,
        secrets: scene.secrets,
        notes: scene.notes,
      }
    })

    const packedEncounters = encounters.value.map(
      (encounter): ContentPackEncounter => ({
        title: encounter.title,
        sceneKey: encounter.scene_id ? (sceneKeys.get(encounter.scene_id) ?? '') : '',
        combatants: combatants.value
          .filter(
            (combatant) =>
              combatant.encounter_id === encounter.id &&
              combatant.kind !== 'pc' &&
              !combatant.source_character_id,
          )
          .map((combatant) => ({
            name: combatant.name,
            kind: combatant.kind,
            initiative: combatant.initiative,
            armorClass: combatant.armor_class,
            maxHp: combatant.max_hp,
            currentHp: combatant.current_hp,
            tempHp: combatant.temp_hp,
            conditions: [...combatant.conditions],
          })),
      }),
    )

    const pack: DmContentPack = {
      version: 1,
      run: {
        title: run.value.title,
        plannedMinutes: run.value.planned_minutes,
        overview,
      },
      scenes: packedScenes,
      encounters: packedEncounters,
    }
    const blob = new Blob([JSON.stringify(pack, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = contentPackFilename(run.value.title)
    anchor.click()
    URL.revokeObjectURL(url)
    showToast('Content pack exported', 'success')
  } catch (error) {
    console.warn('Failed to export content pack', error)
    showToast('Failed to export the content pack', 'error')
  } finally {
    exporting.value = false
  }
}

onMounted(() => {
  setTimer()
  initialize()
})

onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
})

watch(campaignId, initialize)
</script>

<template>
  <main class="dm-page">
    <div v-if="loading" class="state-card">Opening the DM screen...</div>

    <section v-else-if="!isDm" class="state-card state-card--locked">
      <span class="state-icon" aria-hidden="true">◆</span>
      <h1>Behind the screen</h1>
      <p>This workspace is private to the campaign owner.</p>
      <RouterLink to="/" class="button button--primary">Return to campaign</RouterLink>
    </section>

    <section v-else-if="schemaMissing" class="state-card">
      <span class="state-icon" aria-hidden="true">⚙</span>
      <h1>DM workspace needs its migration</h1>
      <p>
        Apply migrations <code>008</code> and <code>009</code> to Supabase, then refresh this page.
      </p>
    </section>

    <section v-else-if="!run" class="setup-card">
      <div class="setup-copy">
        <p class="eyebrow">DM screen / {{ campaignName }}</p>
        <h1>Build your one-shot run sheet.</h1>
        <p>
          Lay out the beats, set a table-time target, then run the whole night from one calm
          workspace.
        </p>
      </div>
      <div class="setup-options">
        <form class="setup-form" @submit.prevent="createRun">
          <label>
            <span>Run sheet title</span>
            <input v-model="setupTitle" type="text" placeholder="The lantern under Blackmere" />
          </label>
          <label>
            <span>Table time</span>
            <div class="input-with-suffix">
              <input v-model.number="setupMinutes" type="number" min="15" max="720" step="15" />
              <span>minutes</span>
            </div>
          </label>
          <button class="button button--primary button--large" type="submit" :disabled="saving">
            {{ saving ? 'Preparing...' : 'Create blank run sheet' }}
          </button>
        </form>
        <div class="setup-divider"><span>or start from a content pack</span></div>
        <button
          class="starter-pack-button"
          type="button"
          :disabled="loadingStarterPack"
          @click="loadStarterPack"
        >
          <span aria-hidden="true">✦</span>
          <span>
            <strong>The Road to Candlekeep</strong>
            <small>Load the bundled seven-scene draft</small>
          </span>
          <i aria-hidden="true">→</i>
        </button>
        <button class="button button--quiet button--block" type="button" @click="openImporter">
          Import another JSON pack
        </button>
      </div>
    </section>

    <template v-else>
      <header class="workspace-header">
        <div>
          <p class="eyebrow">Private DM workspace / {{ campaignName }}</p>
          <h1>{{ run.title }}</h1>
          <p>{{ orderedScenes.length }} scenes · {{ run.planned_minutes }} minute table target</p>
        </div>
        <div class="header-actions">
          <div class="mode-switch" aria-label="DM workspace mode">
            <button :class="{ active: mode === 'prep' }" type="button" @click="mode = 'prep'">
              Prep
            </button>
            <button :class="{ active: mode === 'run' }" type="button" @click="mode = 'run'">
              Run
            </button>
          </div>
          <button
            v-if="run.status === 'prep'"
            class="button button--live"
            type="button"
            :disabled="saving"
            @click="startRun"
          >
            Start one-shot
          </button>
          <span v-else-if="run.status === 'running'" class="live-badge"><i></i> Live</span>
          <span v-else class="complete-badge">Complete</span>
        </div>
      </header>

      <section v-if="mode === 'prep'" class="prep-layout">
        <aside class="panel scene-list-panel">
          <div class="panel-heading">
            <div>
              <span class="panel-kicker">Story order</span>
              <h2>Scenes</h2>
            </div>
            <button class="text-button" type="button" @click="resetSceneForm">+ New</button>
          </div>
          <p v-if="orderedScenes.length === 0" class="empty-copy">
            Add the opening beat, then build toward the finale.
          </p>
          <ol v-else class="scene-list">
            <li
              v-for="(scene, index) in orderedScenes"
              :key="scene.id"
              :class="[`scene--${scene.status}`, { selected: selectedSceneId === scene.id }]"
            >
              <button class="scene-select" type="button" @click="editScene(scene)">
                <span class="scene-number">{{ String(index + 1).padStart(2, '0') }}</span>
                <span class="scene-list-copy">
                  <strong>{{ scene.title }}</strong>
                  <small>{{ scene.estimated_minutes }} min · {{ scene.status }}</small>
                </span>
              </button>
              <div class="scene-order-actions">
                <button
                  type="button"
                  :disabled="index === 0"
                  aria-label="Move scene up"
                  @click="moveScene(scene, -1)"
                >
                  ↑
                </button>
                <button
                  type="button"
                  :disabled="index === orderedScenes.length - 1"
                  aria-label="Move scene down"
                  @click="moveScene(scene, 1)"
                >
                  ↓
                </button>
              </div>
            </li>
          </ol>
        </aside>

        <section class="panel scene-editor-panel">
          <div class="panel-heading">
            <div>
              <span class="panel-kicker">{{ sceneEditingId ? 'Edit beat' : 'Add a beat' }}</span>
              <h2>{{ sceneEditingId ? 'Scene details' : 'New scene' }}</h2>
            </div>
            <button v-if="sceneEditingId" class="text-button" type="button" @click="resetSceneForm">
              Cancel
            </button>
          </div>
          <form class="scene-form" @submit.prevent="saveScene">
            <div class="field-row">
              <label class="field field--grow">
                <span>Scene title</span>
                <input
                  v-model="sceneForm.title"
                  type="text"
                  placeholder="Arrival at the flooded chapel"
                />
              </label>
              <label class="field field--time">
                <span>Target</span>
                <div class="input-with-suffix">
                  <input
                    v-model.number="sceneForm.estimated_minutes"
                    type="number"
                    min="0"
                    max="480"
                    step="5"
                  />
                  <span>min</span>
                </div>
              </label>
            </div>
            <label class="field">
              <span>Purpose <em>What must this beat accomplish?</em></span>
              <input
                v-model="sceneForm.purpose"
                type="text"
                placeholder="Introduce the curse and give the party two routes forward"
              />
            </label>
            <label class="field">
              <span>Read aloud</span>
              <textarea
                v-model="sceneForm.read_aloud"
                rows="4"
                placeholder="The bell rings once beneath the black water..."
              ></textarea>
            </label>
            <div class="field-row field-row--split">
              <label class="field">
                <span>Secrets & clues</span>
                <textarea
                  v-model="sceneForm.secrets"
                  rows="5"
                  placeholder="What the players can discover—and how flexible the clue can be."
                ></textarea>
              </label>
              <label class="field">
                <span>DM notes</span>
                <textarea
                  v-model="sceneForm.notes"
                  rows="5"
                  placeholder="NPC motives, checks, contingencies, treasure..."
                ></textarea>
              </label>
            </div>
            <div class="form-actions">
              <button
                v-if="sceneEditingId && selectedScene"
                class="button button--danger-quiet"
                type="button"
                @click="deleteScene(selectedScene)"
              >
                Delete scene
              </button>
              <button class="button button--primary" type="submit" :disabled="saving">
                {{ sceneEditingId ? 'Save scene' : 'Add scene' }}
              </button>
            </div>
          </form>
        </section>

        <aside class="panel run-settings-panel">
          <div class="panel-heading">
            <div>
              <span class="panel-kicker">Table plan</span>
              <h2>Run settings</h2>
            </div>
          </div>
          <label class="field">
            <span>Title</span>
            <input v-model="setupTitle" type="text" />
          </label>
          <label class="field">
            <span>Table time</span>
            <div class="input-with-suffix">
              <input v-model.number="setupMinutes" type="number" min="15" max="720" step="15" />
              <span>minutes</span>
            </div>
          </label>
          <div class="plan-total">
            <span>Scene plan</span>
            <strong
              >{{
                orderedScenes.reduce((total, scene) => total + scene.estimated_minutes, 0)
              }}
              min</strong
            >
          </div>
          <button class="button button--quiet button--block" type="button" @click="saveRunSettings">
            Save settings
          </button>
          <button
            class="button button--quiet button--block"
            type="button"
            :disabled="exporting"
            @click="exportContentPack"
          >
            {{ exporting ? 'Exporting...' : 'Export content pack' }}
          </button>
          <button
            v-if="run.status === 'running'"
            class="button button--live button--block"
            type="button"
            @click="mode = 'run'"
          >
            Return to live screen
          </button>
        </aside>
      </section>

      <template v-if="mode === 'run'">
        <section class="live-strip">
          <div class="clock-block">
            <span class="panel-kicker">Elapsed table time</span>
            <strong>{{ clockLabel }}</strong>
            <button v-if="run.status === 'running'" type="button" @click="resetClock">
              Reset clock
            </button>
          </div>
          <div class="pace-block">
            <div class="pace-labels">
              <span>{{ elapsedMinutes }} min elapsed</span>
              <span>{{ run.planned_minutes }} min target</span>
            </div>
            <div class="pace-track"><span :style="{ width: `${pacePercent}%` }"></span></div>
            <p>{{ paceMessage }}</p>
          </div>
          <div class="progress-block">
            <span class="panel-kicker">Story progress</span>
            <strong>{{ completedSceneCount }}/{{ orderedScenes.length }}</strong>
            <span>scenes complete</span>
          </div>
        </section>

        <section class="run-layout">
          <aside class="panel run-scene-rail">
            <div class="panel-heading compact">
              <div>
                <span class="panel-kicker">Run of show</span>
                <h2>Scenes</h2>
              </div>
            </div>
            <ol class="run-scene-list">
              <li
                v-for="(scene, index) in orderedScenes"
                :key="scene.id"
                :class="[`scene--${scene.status}`, { selected: selectedSceneId === scene.id }]"
              >
                <button type="button" @click="selectedSceneId = scene.id">
                  <span>{{ String(index + 1).padStart(2, '0') }}</span>
                  <span
                    ><strong>{{ scene.title }}</strong
                    ><small>{{ scene.estimated_minutes }} min</small></span
                  >
                  <i></i>
                </button>
                <button
                  v-if="scene.status !== 'current'"
                  class="scene-jump"
                  type="button"
                  @click="makeSceneCurrent(scene)"
                >
                  Run
                </button>
              </li>
            </ol>
          </aside>

          <section class="panel stage-panel">
            <template v-if="currentScene">
              <div class="stage-heading">
                <div>
                  <span class="panel-kicker">Current scene</span>
                  <h2>{{ currentScene.title }}</h2>
                  <p>
                    {{
                      currentScene.purpose ||
                      'Keep the story moving and follow the players’ energy.'
                    }}
                  </p>
                </div>
                <span class="scene-time">{{ currentScene.estimated_minutes }} min</span>
              </div>
              <article v-if="currentScene.read_aloud" class="read-aloud">
                <div class="content-heading">
                  <span>Read aloud</span><button type="button" @click="copyReadAloud">Copy</button>
                </div>
                <p>{{ currentScene.read_aloud }}</p>
              </article>
              <div class="stage-notes-grid">
                <article>
                  <span class="content-label">Secrets & clues</span>
                  <p>{{ currentScene.secrets || 'No secrets prepared for this scene.' }}</p>
                </article>
                <article>
                  <span class="content-label">DM notes</span>
                  <p>{{ currentScene.notes || 'No additional notes.' }}</p>
                </article>
              </div>
              <div class="stage-actions">
                <button
                  class="button button--quiet"
                  type="button"
                  @click="editSceneInPrep(currentScene)"
                >
                  Edit scene
                </button>
                <div>
                  <span v-if="nextScene">Next: {{ nextScene.title }}</span>
                  <button class="button button--primary" type="button" @click="advanceScene">
                    {{ nextScene ? 'Complete & advance' : 'Complete final scene' }}
                  </button>
                </div>
              </div>
            </template>
            <div v-else class="empty-stage">
              <span aria-hidden="true">✦</span>
              <h2>Every prepared scene is complete.</h2>
              <p>
                Keep improvising, jump back to a scene, or close the one-shot when the epilogue
                lands.
              </p>
            </div>
          </section>

          <aside class="run-sidebar">
            <section class="panel capture-panel">
              <div class="panel-heading compact">
                <div>
                  <span class="panel-kicker">Private log</span>
                  <h2>Quick capture</h2>
                </div>
              </div>
              <form @submit.prevent="addCapture">
                <select v-model="captureType" aria-label="Capture type">
                  <option>Discovery</option>
                  <option>NPC</option>
                  <option>Decision</option>
                  <option>Reminder</option>
                  <option>Campaign thread</option>
                </select>
                <textarea
                  v-model="captureText"
                  rows="3"
                  placeholder="What changed at the table?"
                ></textarea>
                <button class="button button--primary button--block" type="submit">Capture</button>
              </form>
              <RouterLink
                v-if="run.log_note_id"
                :to="{ path: '/notes', query: { note: run.log_note_id } }"
                class="panel-link"
                >Open full DM log ↗</RouterLink
              >
              <small>Campaign threads are shared. Every other capture stays private.</small>
            </section>
            <section class="panel party-snapshot">
              <div class="panel-heading compact">
                <div>
                  <span class="panel-kicker">At the table</span>
                  <h2>Party</h2>
                </div>
                <RouterLink to="/healer">Health ↗</RouterLink>
              </div>
              <p v-if="party.length === 0" class="empty-copy">No active player characters yet.</p>
              <div v-else class="party-list">
                <div v-for="character in party" :key="character.id" class="party-row">
                  <span class="party-avatar"
                    ><img v-if="character.avatar_url" :src="character.avatar_url" alt="" /><template
                      v-else
                      >{{ character.character_name.charAt(0) }}</template
                    ></span
                  >
                  <span
                    ><strong>{{ character.character_name }}</strong
                    ><i
                      ><b
                        :style="{ width: `${hpPercent(character.current_hp, character.max_hp)}%` }"
                      ></b></i
                  ></span>
                  <small
                    >{{ character.current_hp }}/{{ character.max_hp || '?'
                    }}<em v-if="character.temp_hp"> +{{ character.temp_hp }}</em></small
                  >
                </div>
              </div>
            </section>
          </aside>
        </section>
      </template>

      <section class="panel encounter-desk">
        <div class="encounter-header">
          <div>
            <span class="panel-kicker">Combat desk</span>
            <h2>Encounters</h2>
            <p>Prepare the opposition, then run initiative without leaving the DM screen.</p>
          </div>
          <form class="encounter-create" @submit.prevent="createEncounter">
            <input
              v-model="encounterTitle"
              type="text"
              placeholder="Encounter name"
              aria-label="Encounter name"
            />
            <select v-model="encounterSceneId" aria-label="Linked scene">
              <option value="">No linked scene</option>
              <option v-for="scene in orderedScenes" :key="scene.id" :value="scene.id">
                {{ scene.title }}
              </option>
            </select>
            <button class="button button--primary" type="submit">Add encounter</button>
          </form>
        </div>

        <div v-if="encounters.length === 0" class="encounter-empty">
          <span aria-hidden="true">⚔</span>
          <p>No encounters prepared. Add one when a scene needs initiative.</p>
        </div>
        <template v-else>
          <div class="encounter-tabs">
            <button
              v-for="encounter in encounters"
              :key="encounter.id"
              type="button"
              :class="{ active: selectedEncounterId === encounter.id, live: encounter.is_active }"
              @click="selectedEncounterId = encounter.id"
            >
              <i></i>{{ encounter.title }}
            </button>
          </div>

          <template v-if="selectedEncounter">
            <div class="encounter-toolbar">
              <div>
                <h3>{{ selectedEncounter.title }}</h3>
                <span>{{ sceneForEncounter(selectedEncounter) }}</span>
              </div>
              <div v-if="selectedEncounter.is_active" class="initiative-nav">
                <button type="button" aria-label="Previous turn" @click="moveTurn(-1)">←</button>
                <span
                  >Round <strong>{{ selectedEncounter.round }}</strong
                  ><small>{{ activeCombatant?.name ?? 'No combatants' }}’s turn</small></span
                >
                <button type="button" aria-label="Next turn" @click="moveTurn(1)">→</button>
              </div>
              <div class="toolbar-actions">
                <button
                  v-if="!selectedEncounter.is_active"
                  class="button button--live"
                  type="button"
                  :disabled="encounterCombatants.length === 0"
                  @click="startEncounter(selectedEncounter)"
                >
                  Start encounter
                </button>
                <button
                  v-else
                  class="button button--quiet"
                  type="button"
                  @click="endEncounter(selectedEncounter)"
                >
                  End encounter
                </button>
                <button
                  class="icon-button danger"
                  type="button"
                  aria-label="Delete encounter"
                  @click="deleteEncounter(selectedEncounter)"
                >
                  ×
                </button>
              </div>
            </div>

            <div class="combatant-add-row">
              <button class="button button--quiet" type="button" @click="addPartyToEncounter">
                + Add party
              </button>
              <form @submit.prevent="addCombatant">
                <input
                  v-model="combatantForm.name"
                  type="text"
                  placeholder="Goblin scout"
                  aria-label="Combatant name"
                />
                <select v-model="combatantForm.kind" aria-label="Combatant kind">
                  <option value="enemy">Enemy</option>
                  <option value="ally">Ally</option>
                </select>
                <input
                  v-model="combatantForm.initiative"
                  type="number"
                  placeholder="Init"
                  aria-label="Initiative"
                />
                <input
                  v-model="combatantForm.armor_class"
                  type="number"
                  min="0"
                  placeholder="AC"
                  aria-label="Armor class"
                />
                <input
                  v-model.number="combatantForm.max_hp"
                  type="number"
                  min="0"
                  placeholder="HP"
                  aria-label="Maximum hit points"
                />
                <button class="button button--primary" type="submit">Add</button>
              </form>
            </div>

            <p v-if="encounterCombatants.length === 0" class="empty-copy encounter-no-combatants">
              Add the party and opposition to build initiative.
            </p>
            <div v-else class="initiative-table-wrap">
              <table class="initiative-table">
                <thead>
                  <tr>
                    <th>Turn</th>
                    <th>Combatant</th>
                    <th>Init</th>
                    <th>AC</th>
                    <th>Hit points</th>
                    <th>Conditions</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(combatant, index) in encounterCombatants"
                    :key="combatant.id"
                    :class="[
                      {
                        active: activeCombatant?.id === combatant.id,
                        down: combatant.current_hp === 0,
                      },
                      `kind--${combatant.kind}`,
                    ]"
                  >
                    <td>
                      <button
                        class="turn-order"
                        type="button"
                        :disabled="!selectedEncounter.is_active"
                        @click="jumpToTurn(combatant)"
                      >
                        {{ index + 1 }}
                      </button>
                    </td>
                    <td>
                      <span class="combatant-name"
                        ><i></i><strong>{{ combatant.name }}</strong
                        ><small>{{ combatant.kind }}</small></span
                      >
                    </td>
                    <td>
                      <input
                        :value="combatant.initiative ?? ''"
                        type="number"
                        aria-label="Initiative"
                        @change="saveCombatantNumber(combatant, 'initiative', $event)"
                      />
                    </td>
                    <td>
                      <input
                        :value="combatant.armor_class ?? ''"
                        type="number"
                        min="0"
                        aria-label="Armor class"
                        @change="saveCombatantNumber(combatant, 'armor_class', $event)"
                      />
                    </td>
                    <td>
                      <div class="combat-hp">
                        <span
                          ><strong>{{ combatant.current_hp }}</strong
                          >/{{ combatant.max_hp
                          }}<em v-if="combatant.temp_hp"> +{{ combatant.temp_hp }}</em></span
                        >
                        <div class="mini-hp">
                          <i
                            :style="{
                              width: `${hpPercent(combatant.current_hp, combatant.max_hp)}%`,
                            }"
                          ></i>
                        </div>
                        <div>
                          <input
                            v-model.number="hpAmounts[combatant.id]"
                            type="number"
                            min="0"
                            placeholder="0"
                            aria-label="Hit point amount"
                          /><button type="button" @click="applyHp(combatant, 'damage')">−</button
                          ><button type="button" @click="applyHp(combatant, 'heal')">+</button>
                        </div>
                      </div>
                    </td>
                    <td>
                      <input
                        v-model="conditionDrafts[combatant.id]"
                        class="condition-input"
                        type="text"
                        placeholder="poisoned, prone"
                        aria-label="Conditions"
                        @change="saveConditions(combatant)"
                      />
                    </td>
                    <td>
                      <div class="row-actions">
                        <button
                          v-if="combatant.kind !== 'pc'"
                          type="button"
                          title="Duplicate"
                          @click="duplicateCombatant(combatant)"
                        >
                          ⧉</button
                        ><button type="button" title="Remove" @click="removeCombatant(combatant)">
                          ×
                        </button>
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </template>
        </template>
      </section>

      <footer v-if="run.status === 'running'" class="run-footer">
        <span>The screen is private. Only explicit campaign threads are shared with players.</span>
        <button class="button button--danger-quiet" type="button" @click="completeRun">
          End one-shot
        </button>
      </footer>
      <section v-else-if="run.status === 'completed'" class="completion-card">
        <span aria-hidden="true">✦</span>
        <div>
          <strong>Run complete</strong>
          <p>Your scenes, encounters, and private DM log are saved.</p>
        </div>
        <button class="button button--quiet" type="button" @click="planAnotherRun">
          Plan another run
        </button>
      </section>
    </template>
  </main>

  <Teleport to="body">
    <div v-if="importDialogOpen" class="import-backdrop" @click.self="closeImporter">
      <section
        class="import-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="import-dialog-title"
      >
        <header class="import-dialog-header">
          <div>
            <span class="panel-kicker">Portable DM data</span>
            <h2 id="import-dialog-title">Import a content pack</h2>
            <p>Preview the complete run sheet before anything is added to this campaign.</p>
          </div>
          <button type="button" aria-label="Close importer" @click="closeImporter">×</button>
        </header>

        <div class="import-input-grid">
          <div class="import-source-actions">
            <button
              class="button button--starter button--block"
              type="button"
              :disabled="loadingStarterPack"
              @click="loadStarterPack"
            >
              {{ loadingStarterPack ? 'Loading draft...' : 'Load Candlekeep draft' }}
            </button>
            <label class="button button--quiet button--block file-button">
              Choose JSON file
              <input type="file" accept="application/json,.json" @change="onContentPackFile" />
            </label>
          </div>
          <label class="import-json-field">
            <span>Or paste content-pack JSON</span>
            <textarea
              v-model="importText"
              rows="8"
              spellcheck="false"
              placeholder='{ "version": 1, "run": { ... } }'
            ></textarea>
            <button class="button button--quiet" type="button" @click="previewImportText()">
              Preview pasted JSON
            </button>
          </label>
        </div>

        <p v-if="importError" class="import-error" role="alert">{{ importError }}</p>

        <section v-if="importPack" class="import-preview">
          <div class="preview-heading">
            <div>
              <span class="panel-kicker">Ready to import · {{ importSourceName }}</span>
              <h3>{{ importPack.run.title }}</h3>
            </div>
            <div class="preview-metrics">
              <span
                ><strong>{{ importPack.scenes.length }}</strong> scenes</span
              >
              <span
                ><strong>{{ importPack.encounters.length }}</strong> encounters</span
              >
              <span
                ><strong>{{ importPack.run.plannedMinutes }}</strong> min table time</span
              >
              <span
                ><strong>{{ importSceneMinutes }}</strong> min scene plan</span
              >
            </div>
          </div>
          <ol class="preview-scene-list">
            <li v-for="(scene, index) in importPack.scenes" :key="scene.key">
              <span>{{ String(index + 1).padStart(2, '0') }}</span>
              <strong>{{ scene.title }}</strong>
              <small>{{ scene.estimatedMinutes }} min</small>
            </li>
          </ol>
          <p>
            The run, private briefing, scenes, encounters, and non-player combatants will be added
            together. Your active party remains dynamic.
          </p>
        </section>

        <footer class="import-dialog-footer">
          <button
            class="button button--quiet"
            type="button"
            :disabled="importing"
            @click="closeImporter"
          >
            Cancel
          </button>
          <button
            class="button button--primary"
            type="button"
            :disabled="!importPack || importing"
            @click="importContentPack"
          >
            {{ importing ? 'Importing everything...' : 'Import run sheet' }}
          </button>
        </footer>
      </section>
    </div>
  </Teleport>
</template>

<style scoped>
.dm-page {
  min-height: 70vh;
  padding: 1.5rem;
  color: var(--dnd-ink);
}

button,
input,
select,
textarea {
  font: inherit;
}

button {
  color: inherit;
}

.eyebrow,
.panel-kicker,
.content-label {
  color: var(--dnd-accent);
  font-size: 0.66rem;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
}

.panel {
  border: 1px solid rgba(32, 36, 42, 0.11);
  border-radius: 10px;
  background: var(--dnd-elevated);
  box-shadow: 0 4px 14px rgba(32, 36, 42, 0.05);
}

.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  min-height: 2.4rem;
  padding: 0.55rem 0.85rem;
  border: 1px solid transparent;
  border-radius: 7px;
  font-size: 0.78rem;
  font-weight: 700;
  cursor: pointer;
}

.button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.button--primary {
  background: var(--dnd-accent);
  color: var(--dnd-on-accent);
}

.button--live {
  background: #37694f;
  color: #fff;
}

.button--starter {
  background: #b88635;
  color: #fffdf8;
}

.button--quiet {
  border-color: rgba(32, 36, 42, 0.13);
  background: var(--dnd-input-bg);
}

.button--danger-quiet {
  border-color: rgba(169, 76, 61, 0.25);
  background: rgba(169, 76, 61, 0.08);
  color: var(--dnd-accent);
}

.button--large {
  min-height: 3rem;
  padding-inline: 1.25rem;
}

.button--block {
  width: 100%;
}

.state-card,
.setup-card {
  max-width: 760px;
  margin: 4rem auto;
  padding: 2rem;
  border: 1px solid rgba(32, 36, 42, 0.12);
  border-top: 4px solid var(--dnd-accent-2);
  border-radius: 12px;
  background: var(--dnd-elevated);
  text-align: center;
}

.state-card h1,
.setup-card h1,
.workspace-header h1,
.panel-heading h2,
.encounter-header h2,
.stage-heading h2,
.empty-stage h2 {
  font-family: 'Spectral', serif;
  font-weight: 700;
}

.state-card h1 {
  margin: 0.5rem 0;
  font-size: 2rem;
}

.state-card p {
  margin-bottom: 1.2rem;
  color: var(--dnd-muted);
}

.state-card code {
  color: var(--dnd-ink);
}

.state-icon {
  color: var(--dnd-accent-2);
  font-size: 1.8rem;
}

.setup-card {
  display: grid;
  grid-template-columns: 1.2fr 0.8fr;
  gap: 2rem;
  text-align: left;
}

.setup-copy h1 {
  margin: 0.35rem 0 0.75rem;
  font-size: clamp(2rem, 5vw, 3rem);
  line-height: 1;
}

.setup-copy > p:last-child {
  color: var(--dnd-muted);
  line-height: 1.6;
}

.setup-form,
.scene-form {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
}

.setup-options {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
}

.setup-divider {
  display: flex;
  align-items: center;
  gap: 0.65rem;
  color: var(--dnd-muted);
  font-size: 0.62rem;
  text-transform: uppercase;
}

.setup-divider::before,
.setup-divider::after {
  height: 1px;
  flex: 1;
  background: rgba(32, 36, 42, 0.1);
  content: '';
}

.starter-pack-button {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 0.75rem;
  width: 100%;
  padding: 0.8rem;
  border: 1px solid rgba(184, 134, 53, 0.3);
  border-radius: 8px;
  background: rgba(184, 134, 53, 0.1);
  color: var(--dnd-ink);
  text-align: left;
  cursor: pointer;
}

.starter-pack-button:disabled {
  opacity: 0.55;
  cursor: wait;
}

.starter-pack-button > span:first-child {
  color: var(--dnd-accent-2);
  font-size: 1.2rem;
}

.starter-pack-button > span:nth-child(2) {
  display: flex;
  min-width: 0;
  flex-direction: column;
}

.starter-pack-button strong {
  font-family: 'Spectral', serif;
  font-size: 0.9rem;
}

.starter-pack-button small {
  color: var(--dnd-muted);
  font-size: 0.65rem;
}

.starter-pack-button i {
  color: var(--dnd-accent-2);
  font-style: normal;
}

.setup-form label,
.field {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  color: var(--dnd-muted);
  font-size: 0.72rem;
  font-weight: 700;
}

.field span,
.setup-form label > span {
  letter-spacing: 0.04em;
}

.field span em {
  margin-left: 0.35rem;
  font-weight: 400;
}

input,
select,
textarea {
  width: 100%;
  border: 1px solid rgba(32, 36, 42, 0.14);
  border-radius: 7px;
  outline: none;
  background: var(--dnd-input-bg);
  color: var(--dnd-ink);
}

input,
select {
  min-height: 2.45rem;
  padding: 0.5rem 0.65rem;
}

textarea {
  padding: 0.65rem;
  line-height: 1.5;
  resize: vertical;
}

input:focus,
select:focus,
textarea:focus {
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(169, 76, 61, 0.12);
}

.input-with-suffix {
  display: flex;
  align-items: center;
  border: 1px solid rgba(32, 36, 42, 0.14);
  border-radius: 7px;
  background: var(--dnd-input-bg);
}

.input-with-suffix input {
  border: 0;
  box-shadow: none;
}

.input-with-suffix span {
  padding-right: 0.65rem;
  color: var(--dnd-muted);
  font-size: 0.72rem;
}

.workspace-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 1.5rem;
  margin-bottom: 1rem;
  padding: 1.4rem 1.5rem;
  border-radius: 11px;
  background: #20242a;
  color: #f8f5ee;
}

.workspace-header h1 {
  margin: 0.25rem 0 0.15rem;
  color: #fffaf2;
  font-size: clamp(1.7rem, 4vw, 2.6rem);
  line-height: 1.1;
}

.workspace-header p:last-child {
  color: #c3c0b9;
  font-size: 0.78rem;
}

.workspace-header .eyebrow {
  color: #f5c66a;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 0.65rem;
}

.mode-switch {
  display: flex;
  padding: 0.2rem;
  border: 1px solid rgba(255, 255, 255, 0.13);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.05);
}

.mode-switch button {
  min-width: 4.2rem;
  padding: 0.4rem 0.7rem;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: #c3c0b9;
  font-size: 0.76rem;
  font-weight: 700;
  cursor: pointer;
}

.mode-switch button.active {
  background: #fffaf2;
  color: #20242a;
}

.live-badge,
.complete-badge {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  padding: 0.5rem 0.8rem;
  border-radius: 999px;
  background: rgba(78, 139, 112, 0.18);
  color: #a8dfc2;
  font-size: 0.75rem;
  font-weight: 700;
}

.live-badge i {
  width: 0.45rem;
  height: 0.45rem;
  border-radius: 50%;
  background: #68c590;
  box-shadow: 0 0 0 4px rgba(104, 197, 144, 0.15);
}

.complete-badge {
  color: #f5c66a;
  background: rgba(245, 198, 106, 0.12);
}

.prep-layout {
  display: grid;
  grid-template-columns: minmax(220px, 0.72fr) minmax(420px, 1.6fr) minmax(210px, 0.62fr);
  gap: 0.85rem;
}

.scene-list-panel,
.scene-editor-panel,
.run-settings-panel,
.run-scene-rail,
.stage-panel,
.capture-panel,
.party-snapshot,
.encounter-desk {
  padding: 1rem;
}

.panel-heading,
.encounter-header,
.stage-heading {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 0.9rem;
}

.panel-heading.compact {
  margin-bottom: 0.65rem;
}

.panel-heading h2,
.encounter-header h2 {
  margin: 0.15rem 0 0;
  font-size: 1.35rem;
  line-height: 1;
}

.text-button,
.panel-link,
.party-snapshot a {
  padding: 0;
  border: 0;
  background: none;
  color: var(--dnd-accent);
  font-size: 0.73rem;
  font-weight: 700;
  cursor: pointer;
}

.empty-copy {
  color: var(--dnd-muted);
  font-size: 0.78rem;
  line-height: 1.5;
}

.scene-list,
.run-scene-list {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  margin: 0;
  padding: 0;
  list-style: none;
}

.scene-list li {
  display: grid;
  grid-template-columns: 1fr auto;
  border: 1px solid transparent;
  border-radius: 7px;
  background: var(--dnd-input-bg);
}

.scene-list li.selected {
  border-color: var(--dnd-accent-2);
}

.scene-select {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.6rem;
  min-width: 0;
  padding: 0.65rem;
  border: 0;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.scene-number {
  color: var(--dnd-accent-2);
  font-family: ui-monospace, monospace;
  font-size: 0.72rem;
  font-weight: 700;
}

.scene-list-copy {
  display: flex;
  min-width: 0;
  flex-direction: column;
}

.scene-list-copy strong {
  overflow: hidden;
  font-size: 0.79rem;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scene-list-copy small {
  color: var(--dnd-muted);
  font-size: 0.65rem;
}

.scene-order-actions {
  display: flex;
  flex-direction: column;
  padding: 0.25rem;
}

.scene-order-actions button,
.icon-button,
.row-actions button,
.initiative-nav button,
.turn-order {
  border: 0;
  border-radius: 5px;
  background: transparent;
  color: var(--dnd-muted);
  cursor: pointer;
}

.scene-order-actions button:disabled {
  opacity: 0.25;
}

.scene--completed {
  opacity: 0.58;
}

.scene--current {
  box-shadow: inset 3px 0 var(--dnd-accent);
}

.field-row {
  display: flex;
  gap: 0.75rem;
}

.field--grow {
  flex: 1;
}

.field--time {
  width: 9rem;
}

.field-row--split > * {
  flex: 1;
}

.form-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.6rem;
}

.form-actions .button--danger-quiet {
  margin-right: auto;
}

.run-settings-panel {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.plan-total {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 0.2rem;
  padding: 0.75rem;
  border-radius: 7px;
  background: rgba(184, 134, 53, 0.1);
  color: var(--dnd-muted);
  font-size: 0.75rem;
}

.plan-total strong {
  color: var(--dnd-accent-2);
  font-size: 1rem;
}

.live-strip {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 1.25rem;
  margin-bottom: 0.85rem;
  padding: 0.85rem 1rem;
  border: 1px solid rgba(78, 139, 112, 0.24);
  border-radius: 10px;
  background: rgba(78, 139, 112, 0.08);
}

.clock-block,
.progress-block {
  display: flex;
  flex-direction: column;
}

.clock-block strong {
  font-family: ui-monospace, monospace;
  font-size: 1.65rem;
  line-height: 1.2;
}

.clock-block button {
  align-self: flex-start;
  padding: 0;
  border: 0;
  background: none;
  color: var(--dnd-muted);
  font-size: 0.62rem;
  cursor: pointer;
}

.pace-labels {
  display: flex;
  justify-content: space-between;
  color: var(--dnd-muted);
  font-size: 0.65rem;
}

.pace-track {
  height: 0.45rem;
  overflow: hidden;
  margin: 0.35rem 0;
  border-radius: 999px;
  background: rgba(78, 139, 112, 0.14);
}

.pace-track span {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: #4e8b70;
  transition: width 0.4s;
}

.pace-block p {
  color: var(--dnd-muted);
  font-size: 0.67rem;
}

.progress-block {
  min-width: 6rem;
  align-items: flex-end;
}

.progress-block strong {
  font-family: 'Spectral', serif;
  font-size: 1.5rem;
  line-height: 1.2;
}

.progress-block > span:last-child {
  color: var(--dnd-muted);
  font-size: 0.65rem;
}

.run-layout {
  display: grid;
  grid-template-columns: minmax(210px, 0.68fr) minmax(400px, 1.55fr) minmax(240px, 0.72fr);
  align-items: start;
  gap: 0.85rem;
}

.run-scene-list li {
  position: relative;
  border-radius: 7px;
  background: var(--dnd-input-bg);
}

.run-scene-list li > button:first-child {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 0.55rem;
  width: 100%;
  padding: 0.65rem;
  border: 0;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.run-scene-list button > span:first-child {
  color: var(--dnd-muted);
  font-family: ui-monospace, monospace;
  font-size: 0.65rem;
}

.run-scene-list button > span:nth-child(2) {
  display: flex;
  min-width: 0;
  flex-direction: column;
}

.run-scene-list strong {
  overflow: hidden;
  font-size: 0.75rem;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.run-scene-list small {
  color: var(--dnd-muted);
  font-size: 0.62rem;
}

.run-scene-list i {
  width: 0.45rem;
  height: 0.45rem;
  border-radius: 50%;
  background: rgba(109, 112, 117, 0.35);
}

.run-scene-list .scene--current i {
  background: var(--dnd-accent);
  box-shadow: 0 0 0 4px rgba(169, 76, 61, 0.13);
}

.run-scene-list .scene--completed i {
  background: #4e8b70;
}

.scene-jump {
  position: absolute;
  right: 0.45rem;
  bottom: 0.35rem;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--dnd-accent);
  font-size: 0.58rem;
  font-weight: 700;
  cursor: pointer;
}

.stage-panel {
  min-height: 440px;
}

.stage-heading {
  align-items: flex-start;
  padding-bottom: 0.9rem;
  border-bottom: 1px solid rgba(32, 36, 42, 0.1);
}

.stage-heading h2 {
  margin: 0.25rem 0;
  font-size: clamp(1.7rem, 3vw, 2.4rem);
  line-height: 1;
}

.stage-heading p {
  color: var(--dnd-muted);
  font-size: 0.8rem;
}

.scene-time {
  padding: 0.35rem 0.55rem;
  border-radius: 999px;
  background: rgba(184, 134, 53, 0.12);
  color: var(--dnd-accent-2);
  font-size: 0.7rem;
  font-weight: 700;
  white-space: nowrap;
}

.read-aloud {
  margin: 1rem 0;
  padding: 1rem;
  border-left: 3px solid var(--dnd-accent-2);
  border-radius: 0 8px 8px 0;
  background: rgba(184, 134, 53, 0.08);
}

.content-heading {
  display: flex;
  justify-content: space-between;
  margin-bottom: 0.55rem;
  color: var(--dnd-accent-2);
  font-size: 0.65rem;
  font-weight: 700;
  letter-spacing: 0.13em;
  text-transform: uppercase;
}

.content-heading button {
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--dnd-accent);
  font-size: 0.65rem;
  font-weight: 700;
  cursor: pointer;
  text-transform: none;
}

.read-aloud p {
  white-space: pre-wrap;
  font-family: 'Spectral', serif;
  font-size: 1rem;
  line-height: 1.65;
}

.stage-notes-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.75rem;
}

.stage-notes-grid article {
  min-height: 120px;
  padding: 0.85rem;
  border-radius: 7px;
  background: var(--dnd-input-bg);
}

.stage-notes-grid p {
  margin-top: 0.4rem;
  color: var(--dnd-muted);
  font-size: 0.77rem;
  line-height: 1.55;
  white-space: pre-wrap;
}

.stage-actions {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 1rem;
  margin-top: 1rem;
}

.stage-actions > div {
  display: flex;
  align-items: flex-end;
  flex-direction: column;
  gap: 0.35rem;
}

.stage-actions span {
  color: var(--dnd-muted);
  font-size: 0.65rem;
}

.empty-stage {
  min-height: 400px;
  display: grid;
  place-content: center;
  text-align: center;
}

.empty-stage > span {
  color: var(--dnd-accent-2);
  font-size: 2rem;
}

.empty-stage h2 {
  margin: 0.35rem 0;
}

.empty-stage p {
  max-width: 46ch;
  color: var(--dnd-muted);
  font-size: 0.8rem;
}

.run-sidebar {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
}

.capture-panel form {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.capture-panel .panel-link {
  display: inline-block;
  margin-top: 0.7rem;
}

.capture-panel > small {
  display: block;
  margin-top: 0.55rem;
  color: var(--dnd-muted);
  font-size: 0.6rem;
  line-height: 1.4;
}

.party-list {
  display: flex;
  flex-direction: column;
}

.party-row {
  display: grid;
  grid-template-columns: 1.8rem 1fr auto;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0;
  border-top: 1px solid rgba(32, 36, 42, 0.08);
}

.party-avatar {
  width: 1.8rem;
  height: 1.8rem;
  overflow: hidden;
  display: grid;
  place-items: center;
  border-radius: 50%;
  background: rgba(78, 139, 112, 0.15);
  color: #37694f;
  font-family: 'Spectral', serif;
  font-size: 0.72rem;
  font-weight: 700;
}

.party-avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.party-row > span:nth-child(2) {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 0.2rem;
}

.party-row strong {
  overflow: hidden;
  font-size: 0.72rem;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.party-row i {
  width: 100%;
  height: 0.25rem;
  overflow: hidden;
  border-radius: 999px;
  background: rgba(78, 139, 112, 0.14);
}

.party-row i b {
  display: block;
  height: 100%;
  background: #4e8b70;
}

.party-row small {
  color: var(--dnd-muted);
  font-family: ui-monospace, monospace;
  font-size: 0.6rem;
}

.party-row small em {
  color: #637b9b;
}

.encounter-desk {
  margin-top: 0.85rem;
}

.encounter-header {
  align-items: center;
}

.encounter-header p {
  margin-top: 0.25rem;
  color: var(--dnd-muted);
  font-size: 0.75rem;
}

.encounter-create,
.combatant-add-row,
.combatant-add-row form {
  display: flex;
  align-items: center;
  gap: 0.45rem;
}

.encounter-create input {
  width: 11rem;
}

.encounter-create select {
  width: 10rem;
}

.encounter-empty {
  padding: 2rem;
  border-radius: 8px;
  background: var(--dnd-input-bg);
  color: var(--dnd-muted);
  text-align: center;
}

.encounter-empty span {
  color: var(--dnd-accent-2);
  font-size: 1.5rem;
}

.encounter-empty p {
  font-size: 0.78rem;
}

.encounter-tabs {
  display: flex;
  gap: 0.4rem;
  overflow-x: auto;
  padding-bottom: 0.55rem;
  border-bottom: 1px solid rgba(32, 36, 42, 0.1);
}

.encounter-tabs button {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.45rem 0.7rem;
  border: 1px solid rgba(32, 36, 42, 0.11);
  border-radius: 999px;
  background: var(--dnd-input-bg);
  font-size: 0.7rem;
  font-weight: 700;
  white-space: nowrap;
  cursor: pointer;
}

.encounter-tabs button.active {
  border-color: var(--dnd-accent);
  color: var(--dnd-accent);
}

.encounter-tabs i {
  width: 0.35rem;
  height: 0.35rem;
  border-radius: 50%;
  background: var(--dnd-muted);
}

.encounter-tabs button.live i {
  background: #4e8b70;
  box-shadow: 0 0 0 3px rgba(78, 139, 112, 0.14);
}

.encounter-toolbar {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  gap: 1rem;
  padding: 0.8rem 0;
}

.encounter-toolbar h3 {
  font-family: 'Spectral', serif;
  font-size: 1.3rem;
}

.encounter-toolbar > div:first-child span {
  color: var(--dnd-muted);
  font-size: 0.66rem;
}

.toolbar-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.4rem;
}

.icon-button {
  width: 2.35rem;
  height: 2.35rem;
  font-size: 1.2rem;
}

.icon-button.danger {
  color: var(--dnd-accent);
  background: rgba(169, 76, 61, 0.08);
}

.initiative-nav {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.35rem;
  border-radius: 8px;
  background: rgba(78, 139, 112, 0.1);
}

.initiative-nav button {
  width: 2rem;
  height: 2rem;
  background: var(--dnd-elevated);
  color: #37694f;
}

.initiative-nav span {
  display: flex;
  min-width: 7rem;
  align-items: center;
  flex-direction: column;
  color: var(--dnd-muted);
  font-size: 0.62rem;
  line-height: 1.2;
  text-transform: uppercase;
}

.initiative-nav strong {
  color: var(--dnd-ink);
  font-size: 0.9rem;
}

.initiative-nav small {
  max-width: 12rem;
  overflow: hidden;
  color: #37694f;
  font-weight: 700;
  text-overflow: ellipsis;
  text-transform: none;
  white-space: nowrap;
}

.combatant-add-row {
  justify-content: space-between;
  padding: 0.65rem;
  border-radius: 8px;
  background: var(--dnd-input-bg);
}

.combatant-add-row form input:first-child {
  width: 11rem;
}

.combatant-add-row form select {
  width: 6rem;
}

.combatant-add-row form input:not(:first-child) {
  width: 4.5rem;
}

.encounter-no-combatants {
  padding: 1.5rem;
  text-align: center;
}

.initiative-table-wrap {
  overflow-x: auto;
  margin-top: 0.6rem;
}

.initiative-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.72rem;
}

.initiative-table th {
  padding: 0.4rem;
  color: var(--dnd-muted);
  font-size: 0.58rem;
  letter-spacing: 0.1em;
  text-align: left;
  text-transform: uppercase;
}

.initiative-table td {
  padding: 0.5rem 0.4rem;
  border-top: 1px solid rgba(32, 36, 42, 0.08);
  vertical-align: middle;
}

.initiative-table tr.active {
  background: rgba(78, 139, 112, 0.1);
  box-shadow: inset 3px 0 #4e8b70;
}

.initiative-table tr.down {
  opacity: 0.55;
}

.initiative-table input {
  min-height: 2rem;
  padding: 0.3rem 0.4rem;
  font-size: 0.7rem;
}

.initiative-table td:nth-child(3) input,
.initiative-table td:nth-child(4) input {
  width: 3.5rem;
}

.turn-order {
  width: 1.8rem;
  height: 1.8rem;
  background: var(--dnd-input-bg);
  font-size: 0.65rem;
  font-weight: 700;
}

.combatant-name {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 0.45rem;
  min-width: 9rem;
}

.combatant-name i {
  width: 0.5rem;
  height: 0.5rem;
  grid-row: span 2;
  border-radius: 50%;
  background: var(--dnd-accent);
}

.kind--pc .combatant-name i {
  background: #4e8b70;
}

.kind--ally .combatant-name i {
  background: #637b9b;
}

.combatant-name strong {
  line-height: 1.1;
}

.combatant-name small {
  color: var(--dnd-muted);
  font-size: 0.58rem;
  text-transform: uppercase;
}

.combat-hp {
  min-width: 11rem;
  display: grid;
  grid-template-columns: auto 4.5rem auto;
  align-items: center;
  gap: 0.4rem;
}

.combat-hp > span {
  min-width: 3.2rem;
  font-family: ui-monospace, monospace;
  font-size: 0.65rem;
}

.combat-hp em {
  color: #637b9b;
}

.mini-hp {
  height: 0.3rem;
  overflow: hidden;
  border-radius: 999px;
  background: rgba(78, 139, 112, 0.14);
}

.mini-hp i {
  display: block;
  height: 100%;
  background: #4e8b70;
}

.combat-hp > div:last-child {
  display: flex;
}

.combat-hp input {
  width: 2.8rem;
  border-radius: 5px 0 0 5px;
}

.combat-hp button {
  width: 1.75rem;
  border: 1px solid rgba(32, 36, 42, 0.12);
  border-left: 0;
  background: var(--dnd-elevated);
  cursor: pointer;
}

.combat-hp button:last-child {
  border-radius: 0 5px 5px 0;
  color: #37694f;
}

.condition-input {
  min-width: 9rem;
}

.row-actions {
  display: flex;
}

.row-actions button {
  width: 1.8rem;
  height: 1.8rem;
}

.row-actions button:last-child {
  color: var(--dnd-accent);
}

.run-footer,
.completion-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin-top: 0.85rem;
  padding: 0.75rem 1rem;
  border-radius: 8px;
  background: var(--dnd-input-bg);
  color: var(--dnd-muted);
  font-size: 0.68rem;
}

.completion-card {
  justify-content: flex-start;
}

.completion-card .button {
  margin-left: auto;
}

.completion-card > span {
  color: var(--dnd-accent-2);
  font-size: 1.5rem;
}

.completion-card strong {
  color: var(--dnd-ink);
}

.completion-card p {
  margin: 0;
}

.import-backdrop {
  position: fixed;
  z-index: 1000;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 1rem;
  background: rgba(10, 11, 15, 0.72);
  backdrop-filter: blur(5px);
}

.import-dialog {
  width: min(880px, 100%);
  max-height: calc(100vh - 2rem);
  overflow-y: auto;
  padding: 1.25rem;
  border: 1px solid rgba(32, 36, 42, 0.14);
  border-top: 4px solid var(--dnd-accent-2);
  border-radius: 12px;
  background: var(--dnd-elevated);
  color: var(--dnd-ink);
  box-shadow: 0 24px 70px rgba(0, 0, 0, 0.36);
}

.import-dialog-header,
.preview-heading,
.import-dialog-footer {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 1rem;
}

.import-dialog-header {
  padding-bottom: 1rem;
  border-bottom: 1px solid rgba(32, 36, 42, 0.1);
}

.import-dialog-header h2,
.preview-heading h3 {
  margin: 0.2rem 0;
  font-family: 'Spectral', serif;
  font-weight: 700;
}

.import-dialog-header h2 {
  font-size: 1.7rem;
}

.import-dialog-header p,
.import-preview > p {
  color: var(--dnd-muted);
  font-size: 0.72rem;
}

.import-dialog-header > button {
  width: 2.2rem;
  height: 2.2rem;
  border: 0;
  border-radius: 6px;
  background: var(--dnd-input-bg);
  color: var(--dnd-muted);
  font-size: 1.2rem;
  cursor: pointer;
}

.import-input-grid {
  display: grid;
  grid-template-columns: minmax(180px, 0.55fr) minmax(300px, 1.45fr);
  gap: 0.8rem;
  padding: 1rem 0;
}

.import-source-actions {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.file-button {
  position: relative;
  cursor: pointer;
}

.file-button input {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  opacity: 0;
}

.import-json-field {
  display: flex;
  align-items: flex-start;
  flex-direction: column;
  gap: 0.4rem;
  color: var(--dnd-muted);
  font-size: 0.68rem;
  font-weight: 700;
}

.import-json-field textarea {
  min-height: 9rem;
  font-family: ui-monospace, monospace;
  font-size: 0.65rem;
}

.import-json-field .button {
  align-self: flex-end;
}

.import-error {
  margin-bottom: 0.8rem;
  padding: 0.7rem;
  border: 1px solid rgba(169, 76, 61, 0.22);
  border-radius: 7px;
  background: rgba(169, 76, 61, 0.08);
  color: var(--dnd-accent);
  font-size: 0.72rem;
}

.import-preview {
  padding: 1rem;
  border: 1px solid rgba(184, 134, 53, 0.24);
  border-radius: 9px;
  background: rgba(184, 134, 53, 0.07);
}

.preview-heading {
  align-items: center;
}

.preview-heading h3 {
  font-size: 1.25rem;
}

.preview-metrics {
  display: grid;
  grid-template-columns: repeat(2, auto);
  gap: 0.35rem;
}

.preview-metrics span {
  padding: 0.35rem 0.5rem;
  border-radius: 6px;
  background: var(--dnd-elevated);
  color: var(--dnd-muted);
  font-size: 0.62rem;
}

.preview-metrics strong {
  color: var(--dnd-ink);
}

.preview-scene-list {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.35rem;
  margin: 0.8rem 0;
  padding: 0;
  list-style: none;
}

.preview-scene-list li {
  display: grid;
  grid-template-columns: auto 1fr auto;
  align-items: center;
  gap: 0.45rem;
  padding: 0.45rem 0.55rem;
  border-radius: 6px;
  background: var(--dnd-elevated);
}

.preview-scene-list span,
.preview-scene-list small {
  color: var(--dnd-muted);
  font-family: ui-monospace, monospace;
  font-size: 0.6rem;
}

.preview-scene-list strong {
  overflow: hidden;
  font-size: 0.7rem;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.import-dialog-footer {
  justify-content: flex-end;
  padding-top: 1rem;
}

:global(.dark) .panel,
:global(.dark) .state-card,
:global(.dark) .setup-card,
:global(.dark) .import-dialog {
  border-color: rgba(255, 255, 255, 0.1);
  box-shadow: 0 5px 20px rgba(0, 0, 0, 0.28);
}

:global(.dark) input,
:global(.dark) select,
:global(.dark) textarea,
:global(.dark) .input-with-suffix {
  border-color: rgba(255, 255, 255, 0.12);
}

:global(.dark) .workspace-header {
  border: 1px solid rgba(255, 255, 255, 0.08);
  background: #171a20;
}

@media (max-width: 1050px) {
  .prep-layout {
    grid-template-columns: minmax(220px, 0.7fr) minmax(420px, 1.4fr);
  }

  .run-settings-panel {
    grid-column: 1 / -1;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    align-items: end;
  }

  .run-settings-panel .panel-heading {
    grid-column: 1 / -1;
  }

  .run-layout {
    grid-template-columns: minmax(210px, 0.65fr) minmax(430px, 1.35fr);
  }

  .run-sidebar {
    grid-column: 1 / -1;
    display: grid;
    grid-template-columns: 1fr 1fr;
  }

  .combatant-add-row {
    align-items: stretch;
    flex-direction: column;
  }
}

@media (max-width: 760px) {
  .dm-page {
    padding: 0.75rem;
  }

  .setup-card,
  .prep-layout,
  .run-layout,
  .live-strip {
    grid-template-columns: 1fr;
  }

  .workspace-header,
  .encounter-header,
  .encounter-toolbar {
    align-items: flex-start;
    flex-direction: column;
  }

  .workspace-header {
    display: flex;
  }

  .header-actions {
    width: 100%;
    justify-content: space-between;
  }

  .progress-block {
    align-items: flex-start;
  }

  .run-settings-panel,
  .run-sidebar {
    grid-column: auto;
    display: flex;
  }

  .stage-notes-grid,
  .field-row--split {
    grid-template-columns: 1fr;
    display: grid;
  }

  .encounter-create,
  .combatant-add-row form {
    width: 100%;
    align-items: stretch;
    flex-direction: column;
  }

  .encounter-create input,
  .encounter-create select,
  .combatant-add-row form input:first-child,
  .combatant-add-row form select,
  .combatant-add-row form input:not(:first-child) {
    width: 100%;
  }

  .encounter-toolbar {
    display: flex;
  }

  .import-input-grid,
  .preview-scene-list {
    grid-template-columns: 1fr;
  }

  .preview-heading {
    align-items: flex-start;
    flex-direction: column;
  }

  .toolbar-actions {
    justify-content: flex-start;
  }
}

@media (max-width: 480px) {
  .header-actions,
  .field-row,
  .stage-actions,
  .run-footer {
    align-items: stretch;
    flex-direction: column;
  }

  .mode-switch,
  .mode-switch button {
    flex: 1;
  }

  .field--time {
    width: 100%;
  }

  .run-sidebar {
    grid-template-columns: 1fr;
  }

  .import-backdrop {
    padding: 0;
  }

  .import-dialog {
    max-height: 100vh;
    min-height: 100vh;
    border-radius: 0;
  }

  .preview-metrics {
    grid-template-columns: 1fr 1fr;
    width: 100%;
  }
}
</style>
