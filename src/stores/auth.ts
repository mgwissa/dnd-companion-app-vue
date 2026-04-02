import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { User, Session } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase } from '@/lib/supabase'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const session = ref<Session | null>(null)
  const loading = ref(true)

  const isAuthenticated = computed(() => !!user.value)
  const displayName = computed(
    () => user.value?.user_metadata?.display_name ?? user.value?.email ?? null,
  )

  function setSession(s: Session | null) {
    session.value = s
    user.value = s?.user ?? null
  }

  async function signUp(email: string, password: string, displayNameValue?: string) {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { display_name: displayNameValue ?? email.split('@')[0] },
      },
    })
    if (error) throw error
    return data
  }

  async function signIn(email: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })
    if (error) throw error
    return data
  }

  async function signOut() {
    if (!isSupabaseConfigured) {
      user.value = null
      session.value = null
      return
    }
    const { error } = await supabase.auth.signOut()
    if (error) throw error
    user.value = null
    session.value = null
  }

  async function init() {
    loading.value = true
    try {
      if (!isSupabaseConfigured) {
        setSession(null)
        return
      }
      const { data } = await supabase.auth.getSession()
      setSession(data.session)
    } finally {
      loading.value = false
    }

    if (isSupabaseConfigured) {
      supabase.auth.onAuthStateChange((_event, s) => {
        setSession(s)
      })
    }
  }

  return {
    user,
    session,
    loading,
    isAuthenticated,
    displayName,
    signUp,
    signIn,
    signOut,
    init,
  }
})
