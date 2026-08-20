<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { showToast } from '@/composables/useToast'

const auth = useAuthStore()
const router = useRouter()

const password = ref('')
const confirmPassword = ref('')
const busy = ref(false)
const errorMsg = ref('')

function formatAuthError(err: unknown): string {
  if (err && typeof err === 'object' && 'message' in err) {
    const message = (err as { message: unknown }).message
    if (typeof message === 'string') return message
  }
  return 'Something went wrong while updating your password.'
}

async function handleSubmit() {
  errorMsg.value = ''

  if (password.value.length < 6) {
    errorMsg.value = 'Password must be at least 6 characters.'
    return
  }
  if (password.value !== confirmPassword.value) {
    errorMsg.value = 'Passwords do not match.'
    return
  }

  busy.value = true
  try {
    await auth.updatePassword(password.value)
    showToast('Password updated. Welcome back!', 'success')
    router.push('/')
  } catch (err: unknown) {
    errorMsg.value = formatAuthError(err)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="auth-page">
    <div class="auth-card">
      <h1 class="auth-heading">Choose a New Password</h1>
      <p class="auth-sub">Set a new password for your adventurer account.</p>

      <form class="auth-form" @submit.prevent="handleSubmit">
        <div class="field">
          <label for="new-password" class="label">New password</label>
          <input
            id="new-password"
            v-model="password"
            type="password"
            class="input"
            autocomplete="new-password"
            required
          />
        </div>

        <div class="field">
          <label for="confirm-password" class="label">Confirm password</label>
          <input
            id="confirm-password"
            v-model="confirmPassword"
            type="password"
            class="input"
            autocomplete="new-password"
            required
          />
        </div>

        <div v-if="errorMsg" class="error" role="alert">{{ errorMsg }}</div>

        <button type="submit" class="btn btn-primary" :disabled="busy">
          {{ busy ? 'Updating...' : 'Update Password' }}
        </button>
      </form>

      <p class="toggle-text">
        Remembered it?
        <button type="button" class="toggle-link" @click="router.push('/login')">
          Back to sign in
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
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn-primary {
  background: var(--dnd-accent);
  color: var(--dnd-on-accent);
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
</style>
