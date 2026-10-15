<script setup lang="ts">
import { computed } from 'vue'
import { marked } from 'marked'
import DOMPurify from 'dompurify'

const props = defineProps<{ content: string }>()
// Every consumer (including public recaps) uses this same sanitization boundary.
const html = computed(() => DOMPurify.sanitize(
  marked.parse(props.content, { async: false, gfm: true }),
  { USE_PROFILES: { html: true }, FORBID_TAGS: ['style', 'form'], FORBID_ATTR: ['style'] },
))
</script>

<template>
  <!-- HTML is sanitized above, including unsafe link protocols and event handlers. -->
  <div class="markdown-content" v-html="html" />
</template>

<style scoped>
.markdown-content { color: var(--dnd-ink); font-size: 1rem; line-height: 1.85; overflow-wrap: anywhere; }
.markdown-content :deep(> :first-child) { margin-top: 0; }
.markdown-content :deep(> :last-child) { margin-bottom: 0; }
.markdown-content :deep(h1), .markdown-content :deep(h2), .markdown-content :deep(h3), .markdown-content :deep(h4), .markdown-content :deep(h5), .markdown-content :deep(h6) { font-family: 'Spectral', serif; color: var(--dnd-ink); line-height: 1.3; font-weight: 600; text-wrap: balance; }
.markdown-content :deep(h1) { font-size: 2rem; margin: 2rem 0 1rem; }
.markdown-content :deep(h2) { font-size: 1.55rem; margin: 2.6rem 0 1.1rem; padding-bottom: .65rem; border-bottom: 1px solid color-mix(in srgb, var(--dnd-accent-2) 35%, transparent); }
.markdown-content :deep(h3) { font-size: 1.22rem; margin: 1.8rem 0 .65rem; }
.markdown-content :deep(p) { margin: 0 0 1.1rem; }
.markdown-content :deep(strong) { color: var(--dnd-ink); font-weight: 700; }
.markdown-content :deep(ul), .markdown-content :deep(ol) { padding-inline-start: 1.4rem; margin: .75rem 0 1.4rem; }
.markdown-content :deep(li) { padding-inline-start: .25rem; margin: .45rem 0; }
.markdown-content :deep(li::marker) { color: var(--dnd-accent-2); }
.markdown-content :deep(li > p) { margin-bottom: .4rem; }
.markdown-content :deep(a) { color: var(--dnd-accent); text-decoration: underline; text-underline-offset: 3px; }
.markdown-content :deep(a:hover) { color: var(--dnd-accent-2); }
.markdown-content :deep(blockquote) { margin: 1.5rem 0; padding: .9rem 1.3rem; border-inline-start: 3px solid var(--dnd-accent-2); border-radius: 0 8px 8px 0; background: var(--dnd-input-bg); font-style: italic; }
.markdown-content :deep(blockquote > :last-child) { margin-bottom: 0; }
.markdown-content :deep(code) { padding: .15rem .35rem; background: var(--dnd-input-bg); border-radius: 4px; font-size: .87em; }
.markdown-content :deep(pre) { padding: 1rem; background: var(--dnd-input-bg); border: 1px solid color-mix(in srgb, var(--dnd-muted) 25%, transparent); border-radius: 8px; overflow-x: auto; line-height: 1.6; }
.markdown-content :deep(pre code) { padding: 0; background: none; }
.markdown-content :deep(table) { display: block; max-width: 100%; width: max-content; overflow-x: auto; border-collapse: collapse; margin: 1.25rem 0; font-size: .94em; }
.markdown-content :deep(th), .markdown-content :deep(td) { padding: .7rem 1rem; text-align: start; border: 1px solid color-mix(in srgb, var(--dnd-muted) 30%, transparent); }
.markdown-content :deep(th) { background: var(--dnd-input-bg); font-weight: 600; }
.markdown-content :deep(hr) { border: 0; border-top: 1px solid color-mix(in srgb, var(--dnd-accent-2) 40%, transparent); margin: 2rem 0; }
.markdown-content :deep(img) { max-width: 100%; height: auto; border-radius: 8px; }
.markdown-content :deep(input[type=checkbox]) { accent-color: var(--dnd-accent-2); margin-inline-end: .4rem; }
@media (max-width: 600px) { .markdown-content { font-size: .95rem; } .markdown-content :deep(h2) { font-size: 1.35rem; } }
</style>
