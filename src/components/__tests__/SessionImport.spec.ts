import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import SessionImport from '../SessionImport.vue'

const { rpc, campaign } = vi.hoisted(() => ({
  rpc: vi.fn(),
  campaign: { activeCampaignId: 'campaign-1', activeCampaign: { name: 'Dungeon campaign' } },
}))
vi.mock('@/lib/supabase', () => ({ supabase: { rpc } }))
vi.mock('@/stores/campaign', () => ({ useCampaignStore: () => campaign }))

const source = { version: 1, kind: 'dnd-session', id: 'session-1', title: 'Forest & river',
  recap: 'Darabeth is safe.', resumePoint: 'Gor is next; confirm.', playedOn: null,
  threads: ['Locate aboleth', 'Check music'], transcript: '<script>window.bad = true</script> original speech' }

async function choose(wrapper: ReturnType<typeof mount>, value: unknown) {
  const input = wrapper.get('input[type=file]')
  Object.defineProperty(input.element, 'files', { configurable: true,
    value: [{ size: 100, text: async () => JSON.stringify(value) }] })
  await input.trigger('change')
  await flushPromises()
}

beforeEach(() => { rpc.mockReset(); campaign.activeCampaignId = 'campaign-1' })

describe('reviewed session import', () => {
  it('previews without writing, keeps transcript literal, and saves only chosen threads', async () => {
    rpc.mockResolvedValue({ data: 'note-1', error: null })
    const wrapper = mount(SessionImport)
    await choose(wrapper, source)
    expect(rpc).not.toHaveBeenCalled()
    expect(wrapper.findAll('script')).toHaveLength(0)
    expect(wrapper.get('pre').text()).toBe(source.transcript)
    const checkboxes = wrapper.findAll('input[type=checkbox]')
    expect(checkboxes.every(c => !(c.element as HTMLInputElement).checked)).toBe(true)
    // Removing an unselected suggestion must not shift the selected index.
    await wrapper.get('input[aria-label="Thread 1"]').setValue('')
    await checkboxes[1]!.setValue(true)
    await wrapper.get('form').trigger('submit')
    await flushPromises()
    expect(rpc).toHaveBeenCalledWith('import_session_pack', expect.objectContaining({
      p_campaign_id: 'campaign-1', p_shared: false,
      p_pack: expect.objectContaining({ selectedThreads: ['Check music'], playedOn: null, transcript: source.transcript }),
    }))
    expect(wrapper.emitted('imported')).toEqual([['note-1']])
  })

  it('shows duplicate errors and retains the preview for correction', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '23505' } })
    const wrapper = mount(SessionImport)
    await choose(wrapper, source)
    await wrapper.get('form').trigger('submit')
    await flushPromises()
    expect(wrapper.get('[role=alert]').text()).toContain('already been imported')
    expect(wrapper.find('form').exists()).toBe(true)
    expect(wrapper.emitted('imported')).toBeUndefined()
  })

  it('rejects a malformed file without enabling a save', async () => {
    const wrapper = mount(SessionImport)
    await choose(wrapper, { ...source, threads: [{ title: 'bad' }] })
    expect(wrapper.get('[role=alert]').text()).toContain('threads')
    expect(wrapper.find('form').exists()).toBe(false)
    expect(rpc).not.toHaveBeenCalled()
  })
})
