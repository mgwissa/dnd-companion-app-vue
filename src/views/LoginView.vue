<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { showToast } from '@/composables/useToast'

const auth = useAuthStore()
const router = useRouter()

const mode = ref<'login' | 'register'>('login')
const email = ref('')
const password = ref('')
const displayName = ref('')
const busy = ref(false)
const errorMsg = ref('')

const isLogin = computed(() => mode.value === 'login')
const heading = computed(() => (isLogin.value ? 'Sign In' : 'Create Account'))
const submitLabel = computed(() => (isLogin.value ? 'Sign In' : 'Register'))

function toggleMode() {
  mode.value = isLogin.value ? 'register' : 'login'
  errorMsg.value = ''
}

async function handleSubmit() {
  errorMsg.value = ''
  const e = email.value.trim()
  const p = password.value

  if (!e || !p) {
    errorMsg.value = 'Email and password are required.'
    return
  }
  if (!isLogin.value && p.length < 6) {
    errorMsg.value = 'Password must be at least 6 characters.'
    return
  }

  busy.value = true
  try {
    if (isLogin.value) {
      await auth.signIn(e, p)
      showToast('Welcome back!', 'success')
      router.push('/')
    } else {
      const data = await auth.signUp(e, p, displayName.value.trim() || undefined)
      if (data.session) {
        showToast('Account created!', 'success')
        router.push('/')
      } else {
        showToast('Check your email to confirm your account.', 'info', 5000)
        mode.value = 'login'
      }
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Something went wrong'
    errorMsg.value = message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="auth-page">
    <div class="auth-card">
      <h1 class="auth-heading">{{ heading }}</h1>
      <p class="auth-sub">
        {{ isLogin ? 'Sign in to sync your notes and links.' : 'Join the party — create your account.' }}
      </p>

      <form class="auth-form" @submit.prevent="handleSubmit">
        <div v-if="!isLogin" class="field">
          <label for="auth-name" class="label">Display name</label>
          <input
            id="auth-name"
            v-model="displayName"
            type="text"
            class="input"
            placeholder="Korhal Dawnrender"
            autocomplete="name"
          />
        </div>

        <div class="field">
          <label for="auth-email" class="label">Email</label>
          <input
            id="auth-email"
            v-model="email"
            type="email"
            class="input"
            placeholder="adventurer@example.com"
            autocomplete="email"
            required
          />
        </div>

        <div class="field">
          <label for="auth-password" class="label">Password</label>
          <input
            id="auth-password"
            v-model="password"
            type="password"
            class="input"
            placeholder="••••••••"
            autocomplete="current-password"
            required
          />
        </div>

        <div v-if="errorMsg" class="error" role="alert">{{ errorMsg }}</div>

        <button type="submit" class="btn btn-primary" :disabled="busy">
          {{ busy ? 'Working...' : submitLabel }}
        </button>
      </form>

      <p class="toggle-text">
        {{ isLogin ? "Don't have an account?" : 'Already have an account?' }}
        <button type="button" class="toggle-link" @click="toggleMode">
          {{ isLogin ? 'Register' : 'Sign in' }}
        </button>
      </p>
    </div>
  </main>
</template>

<style scoped>
.auth-page {
  display: flex;
  justify-content: center;
  align-items: flex-start;
  padding: 3rem 1rem 4rem;
  min-height: 60vh;
}

.auth-card {
  width: 100%;
  max-width: 400px;
  padding: 2rem;
  background: var(--dnd-paper);
  border-radius: 12px;
  border: 1px solid rgba(0, 0, 0, 0.06);
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.08);
}

.auth-heading {
  font-family: 'Cinzel', serif;
  font-size: 1.75rem;
  font-weight: 700;
  color: var(--dnd-ink);
  margin: 0 0 0.25rem;
  text-align: center;
}

.auth-sub {
  text-align: center;
  color: var(--dnd-muted);
  font-size: 0.9rem;
  margin: 0 0 1.5rem;
}

.auth-form {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.label {
  font-size: 0.8125rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--dnd-muted);
}

.input {
  padding: 0.6rem 0.75rem;
  border-radius: 8px;
  border: 1px solid rgba(0, 0, 0, 0.12);
  background: var(--dnd-bg);
  color: var(--dnd-ink);
  font-size: 1rem;
  font-family: inherit;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.input::placeholder {
  color: var(--dnd-muted);
}
.input:focus {
  outline: none;
  border-color: var(--dnd-accent);
  box-shadow: 0 0 0 3px rgba(139, 58, 47, 0.15);
}

.error {
  padding: 0.6rem 0.75rem;
  border-radius: 8px;
  background: rgba(179, 58, 42, 0.1);
  border: 1px solid rgba(179, 58, 42, 0.25);
  color: #b33a2a;
  font-size: 0.875rem;
  line-height: 1.4;
}

.btn {
  padding: 0.65rem 1rem;
  border-radius: 8px;
  border: none;
  font-size: 1rem;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  transition: filter 0.15s, opacity 0.15s;
}
.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.btn-primary {
  background: var(--dnd-accent);
  color: var(--dnd-paper);
}
.btn-primary:hover:not(:disabled) {
  filter: brightness(1.1);
}

.toggle-text {
  text-align: center;
  margin: 1.25rem 0 0;
  font-size: 0.875rem;
  color: var(--dnd-muted);
}

.toggle-link {
  background: none;
  border: none;
  color: var(--dnd-accent);
  font-weight: 600;
  font-size: 0.875rem;
  cursor: pointer;
  padding: 0;
  text-decoration: underline;
  text-underline-offset: 2px;
  font-family: inherit;
}
.toggle-link:hover {
  filter: brightness(1.15);
}
</style>
