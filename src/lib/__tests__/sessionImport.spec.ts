import { describe, expect, it } from 'vitest'
import { isPlayedOn, parseSessionPack, sessionBody } from '../sessionImport'

const valid = { version: 1, kind: 'dnd-session', id: 'river-1', title: 'River fight', playedOn: null,
  resumePoint: 'Gor is next; confirm with DM.', recap: 'Darabeth is safe.', threads: ['Find the aboleth'] }

describe('session imports', () => {
  it('accepts unknown dates and keeps transcript content as plain text', () => {
    const pack = parseSessionPack({ ...valid, transcript: '<script>unsafe()</script>\nOriginal speech' })
    expect(pack.playedOn).toBeNull()
    expect(pack.transcript).toContain('<script>')
    expect(sessionBody(pack)).toContain('## Recap\n\nDarabeth is safe.')
    expect(sessionBody(pack)).not.toContain('<script>')
  })
  it('rejects unrelated exports and malformed threads', () => {
    for (const input of [[], null, { ...valid, version: 2 }, { ...valid, threads: [{}] }, { ...valid, recap: '  ' }]) {
      expect(() => parseSessionPack(input)).toThrow()
    }
  })
  it('rejects impossible dates rather than normalizing them', () => {
    expect(isPlayedOn('2026-02-29')).toBe(false)
    expect(isPlayedOn('2024-02-29')).toBe(true)
    expect(isPlayedOn('2026-13-01')).toBe(false)
    expect(() => parseSessionPack({ ...valid, playedOn: '2026-02-30' })).toThrow()
  })
  it('omits empty sections and preserves uncertainty and suggested threads', () => {
    const body = sessionBody(parseSessionPack({ ...valid, uncertainties: 'Potion holders unconfirmed.' }))
    expect(body).not.toContain('## Discoveries')
    expect(body).toContain('## Needs confirmation\n\nPotion holders unconfirmed.')
    expect(body).toContain('- Find the aboleth')
  })
})
