<script setup lang="ts">
import { ref, watch } from 'vue'
import MarkdownContent from '@/components/MarkdownContent.vue'
import { supabase } from '@/lib/supabase'

const props = defineProps<{ token: string }>()
type Recap = { title: string; body: string; resume_point: string; played_on: string | null }
const recap = ref<Recap | null>(null)
const loading = ref(false)
const error = ref('')
watch(() => props.token, async token => {
  recap.value = null
  error.value = ''
  loading.value = true
  try {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(token)) {
      error.value = 'This recap link is unavailable or has been revoked.'
      return
    }
    const { data, error: failure } = await supabase.rpc('get_shared_recap', { p_token: token })
    if (props.token !== token) return
    if (failure) throw failure
    recap.value = (data?.[0] as Recap | undefined) ?? null
    if (!recap.value) error.value = 'This recap link is unavailable or has been revoked.'
  } catch {
    if (props.token === token) error.value = 'Could not load this recap. Please try again.'
  } finally {
    if (props.token === token) loading.value = false
  }
}, { immediate: true })
</script>

<template>
  <article class="shared-recap">
    <p v-if="loading" role="status">Loading session recap…</p>
    <p v-else-if="error" role="alert">{{ error }}</p>
    <template v-else-if="recap">
      <p class="recap-kicker">Campaign journal · Session recap</p>
      <h1>{{ recap.title }}</h1>
      <time v-if="recap.played_on" :datetime="recap.played_on">Played {{ recap.played_on }}</time>
      <section v-if="recap.resume_point" class="resume-point">
        <h2>Where we left off</h2>
        <MarkdownContent :content="recap.resume_point" />
      </section>
      <MarkdownContent :content="recap.body" />
    </template>
  </article>
</template>

<style scoped>
.shared-recap { max-width: 48rem; margin: 0 auto; padding: clamp(1rem, 4vw, 2.5rem); color: var(--dnd-ink); background: var(--dnd-elevated); border: 1px solid color-mix(in srgb, var(--dnd-muted) 22%, transparent); border-top: 3px solid var(--dnd-accent-2); border-radius: 12px; overflow-wrap: anywhere; }
h1, h2 { font-family: 'Spectral', serif; line-height: 1.25; }
h1 { font-size: clamp(1.8rem, 5vw, 2.6rem); margin: .5rem 0 1rem; }
h2 { margin: 1.8rem 0 .7rem; }
p { line-height: 1.8; }
.recap-kicker, time { color: var(--dnd-muted); }
.resume-point { margin: 1.5rem 0; padding: 1rem 1.25rem; background: var(--dnd-input-bg); border-left: 3px solid var(--dnd-accent-2); border-radius: 6px; }
.resume-point h2 { margin-top: 0; }
</style>
