import { flushPromises, mount } from '@vue/test-utils'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import SharedRecapView from '@/views/SharedRecapView.vue'

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }))
vi.mock('@/lib/supabase', () => ({ supabase: { rpc } }))
const token = '12345678-1234-4567-8901-123456789012'

beforeEach(() => rpc.mockReset())

describe('public recap', () => {
  it('reads only the public RPC and safely displays headings, lists, and the stopping point', async () => {
    rpc.mockResolvedValue({ error: null, data: [{ title: 'Riverbank', played_on: null,
      resume_point: 'Gor is next.', body: '## Recap\n\nDarabeth is safe.\n\n- Check the octopus\n- <script>bad()</script>' }] })
    const wrapper = mount(SharedRecapView, { props: { token } })
    await flushPromises()
    expect(rpc).toHaveBeenCalledWith('get_shared_recap', { p_token: token })
    expect(wrapper.get('h1').text()).toBe('Riverbank')
    expect(wrapper.text()).toContain('Gor is next.')
    expect(wrapper.findAll('li')).toHaveLength(2)
    expect(wrapper.findAll('script')).toHaveLength(0)
    expect(wrapper.find('textarea').exists()).toBe(false)
  })
  it('handles revoked links without an authentication redirect', async () => {
    rpc.mockResolvedValue({ error: null, data: [] })
    const wrapper = mount(SharedRecapView, { props: { token } })
    await flushPromises()
    expect(wrapper.get('[role=alert]').text()).toContain('unavailable or has been revoked')
  })
  it('rejects malformed tokens before requesting data', async () => {
    const wrapper = mount(SharedRecapView, { props: { token: 'invalid' } })
    await flushPromises()
    expect(rpc).not.toHaveBeenCalled()
    expect(wrapper.find('h1').exists()).toBe(false)
  })
})
