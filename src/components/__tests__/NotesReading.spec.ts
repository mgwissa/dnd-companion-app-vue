import { flushPromises, mount } from '@vue/test-utils'
import { describe, expect, it, vi } from 'vitest'
import NotesView from '@/views/NotesView.vue'

vi.mock('vue-router', () => ({ useRoute: () => ({ query: { note: 'note-1' } }),
  RouterLink: { template: '<a><slot /></a>' } }))
vi.mock('@/stores/auth', () => ({ useAuthStore: () => ({ user: { id: 'user-1' } }) }))
vi.mock('@/stores/campaign', () => ({ useCampaignStore: () => ({ activeCampaignId: 'campaign-1', activeCampaign: { name: 'Dungeon campaign' } }) }))
vi.mock('@/lib/supabase', () => ({ supabase: { from: (table: string) => {
  const result = Promise.resolve({ error: null, data: table === 'notes' ? [{
      id: 'note-1', user_id: 'user-1', campaign_id: 'campaign-1', title: 'Riverbank', body: '## Recap\n\n**Darabeth** is safe.',
      tags: ['session'], is_shared: false, note_type: 'session', played_on: null, resume_point: 'Gor is next.',
      parent_session_id: null, recap_share_token: null, updated_at: '2026-10-15T12:00:00Z', created_at: '2026-10-15T12:00:00Z',
    }] : [] })
  const query = Object.assign(result, { select: () => query, eq: () => query, order: () => query })
  return query
} } }))

describe('notes journal reading', () => {
  it('opens a saved note formatted and preserves drafts across Edit and Read', async () => {
    const wrapper = mount(NotesView)
    await flushPromises()
    expect(wrapper.get('.journal-body strong').text()).toBe('Darabeth')
    expect(wrapper.find('#editor-body').exists()).toBe(false)
    const edit = wrapper.findAll('.journal-view-toggle button')[1]!
    await edit.trigger('click')
    await wrapper.get('#editor-body').setValue('## Updated\n\n**Jack** woke up.')
    await wrapper.findAll('.journal-view-toggle button')[0]!.trigger('click')
    expect(wrapper.get('.journal-body strong').text()).toBe('Jack')
    expect(wrapper.text()).toContain('Unsaved changes')
    await wrapper.findAll('.journal-view-toggle button')[1]!.trigger('click')
    expect((wrapper.get('#editor-body').element as HTMLTextAreaElement).value).toContain('**Jack**')
    wrapper.unmount()
  })
})
