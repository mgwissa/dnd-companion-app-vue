export interface SessionPack {
  version: 1
  kind: 'dnd-session'
  id: string
  title: string
  playedOn: string | null
  resumePoint: string
  recap: string
  discoveries: string
  npcsAndLocations: string
  loot: string
  uncertainties: string
  threads: string[]
  transcript: string
}

export const sessionSections = [
  ['recap', 'Recap'],
  ['discoveries', 'Discoveries'],
  ['npcsAndLocations', 'NPCs & locations'],
  ['loot', 'Loot & bookkeeping'],
  ['uncertainties', 'Needs confirmation'],
] as const

// Recording references belong in source transcripts, not the reviewed story.
export function removeSessionTimeReferences(content: string): string {
  return content.replace(/[ \t]*\[\d{1,2}:\d{2}(?::\d{2})?(?:[ \t]*[–—-][ \t]*\d{1,2}:\d{2}(?::\d{2})?)?\]/g, '')
}

export function isPlayedOn(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const date = new Date(`${value}T12:00:00Z`)
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value
}

export function parseSessionPack(value: unknown): SessionPack {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Choose a session JSON file.')
  }
  const input = value as Record<string, unknown>
  if (input.version !== 1 || input.kind !== 'dnd-session') {
    throw new Error('This is not a supported session file (dnd-session, version 1).')
  }
  for (const key of ['id', 'title', 'resumePoint', 'recap']) {
    if (typeof input[key] !== 'string' || !input[key].trim()) {
      throw new Error(`Session ${key} is required.`)
    }
  }
  if (input.playedOn != null && !isPlayedOn(input.playedOn)) {
    throw new Error('Played date must be a real date in YYYY-MM-DD format, or null if unknown.')
  }
  for (const key of ['discoveries', 'npcsAndLocations', 'loot', 'uncertainties', 'transcript']) {
    if (input[key] !== undefined && typeof input[key] !== 'string') {
      throw new Error(`Session ${key} must be text.`)
    }
  }
  if (!Array.isArray(input.threads) || input.threads.some((item) => typeof item !== 'string')) {
    throw new Error('Session threads must be a list of text entries.')
  }
  return {
    version: 1, kind: 'dnd-session',
    id: (input.id as string).trim(), title: (input.title as string).trim(),
    playedOn: (input.playedOn as string | null) ?? null,
    resumePoint: removeSessionTimeReferences((input.resumePoint as string).trim()), recap: removeSessionTimeReferences((input.recap as string).trim()),
    discoveries: removeSessionTimeReferences((input.discoveries as string) ?? ''),
    npcsAndLocations: removeSessionTimeReferences((input.npcsAndLocations as string) ?? ''),
    loot: removeSessionTimeReferences((input.loot as string) ?? ''), uncertainties: removeSessionTimeReferences((input.uncertainties as string) ?? ''),
    transcript: (input.transcript as string) ?? '',
    threads: input.threads.filter((item) => item.trim()).map((item) => item.trim()),
  }
}

export function sessionBody(pack: SessionPack): string {
  const sections = sessionSections
    .filter(([key]) => pack[key].trim())
    .map(([key, label]) => `## ${label}\n\n${pack[key].trim()}`)
  if (pack.threads.length) sections.push(`## Open threads\n\n${pack.threads.map((t) => `- ${t}`).join('\n')}`)
  return sections.join('\n\n')
}

export function localPlayedOn(now = new Date()): string {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`
}
