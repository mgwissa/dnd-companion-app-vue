import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import MarkdownContent from '../MarkdownContent.vue'

describe('journal Markdown', () => {
  it('renders formatted text, nested lists, links, tables, and code', () => {
    const wrapper = mount(MarkdownContent, { props: { content: '## Discoveries\n\n**Darabeth** is *safe*. [Map](https://example.com)\n\n1. Riverbank\n   - Gor is next\n\n| Loot | Count |\n| --- | --- |\n| Potions | 2 |\n\n```text\nroll 1d20\n```' } })
    expect(wrapper.get('h2').text()).toBe('Discoveries')
    expect(wrapper.get('strong').text()).toBe('Darabeth')
    expect(wrapper.get('em').text()).toBe('safe')
    expect(wrapper.get('ol ul li').text()).toBe('Gor is next')
    expect(wrapper.get('a').attributes('href')).toBe('https://example.com')
    expect(wrapper.get('table td').text()).toBe('Potions')
    expect(wrapper.get('pre code').text()).toContain('roll 1d20')
  })
  it('strips scripts, unsafe URLs, style injection, and event handlers', () => {
    const wrapper = mount(MarkdownContent, { props: { content: '<script>alert(1)</script>\n\n[bad](javascript:alert%281%29)\n\n<img src="x" onerror="bad()"><style>body{display:none}</style><p style="display:none">Safe text</p>' } })
    expect(wrapper.find('script').exists()).toBe(false)
    expect(wrapper.find('style').exists()).toBe(false)
    expect(wrapper.find('[onerror]').exists()).toBe(false)
    expect(wrapper.find('[style]').exists()).toBe(false)
    expect(wrapper.find('a[href]').exists()).toBe(false)
    expect(wrapper.text()).toContain('Safe text')
  })
})
