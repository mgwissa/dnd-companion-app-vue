import { createClient } from '@supabase/supabase-js'

function readProjectUrl(): string {
  const raw = ((import.meta.env.VITE_SUPABASE_URL as string | undefined) ?? '').trim()
  if (!raw) return ''
  const noTrailingSlash = raw.replace(/\/+$/, '')
  try {
    new URL(noTrailingSlash)
    return noTrailingSlash
  } catch {
    if (import.meta.env.DEV) {
      console.error(
        '[ttrpg-companion] VITE_SUPABASE_URL must be a full URL (e.g. https://xxxx.supabase.co). Check for typos or spaces in .env.local.',
      )
    }
    return ''
  }
}

function readAnonKey(): string {
  return ((import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined) ?? '').trim()
}

const supabaseUrl = readProjectUrl()
const supabaseAnonKey = readAnonKey()

/** Set when both env vars are present. If false, skip auth/network in init so the app can still boot. */
export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

// Valid-shaped placeholders so createClient never throws at import time (throws would block Vue from mounting).
const placeholderUrl = 'https://placeholder.supabase.co'
const placeholderKey =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE2NDM4OTcwMDAsImV4cCI6MTk2MDQ2MzAwMH0.placeholder'

if (!isSupabaseConfigured && import.meta.env.DEV) {
  console.warn(
    '[ttrpg-companion] Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Add a .env.local (see GitHub Actions secrets / Supabase dashboard). Auth and data features stay off until then.',
  )
}

export const supabase = createClient(
  isSupabaseConfigured ? supabaseUrl : placeholderUrl,
  isSupabaseConfigured ? supabaseAnonKey : placeholderKey,
)
