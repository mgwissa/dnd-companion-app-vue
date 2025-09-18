<template>
  <transition name="toast-fade">
    <div
      v-if="toast.visible"
      :class="['dnd-toast', `variant-${toast.variant}`]"
      role="status"
      aria-live="polite"
    >
      <span class="toast-icon" aria-hidden>
        <svg
          v-if="toast.variant === 'success'"
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M20 6L9 17l-5-5" />
        </svg>
        <svg
          v-else-if="toast.variant === 'error'"
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <circle cx="12" cy="12" r="10" />
          <line x1="15" y1="9" x2="9" y2="15" />
          <line x1="9" y1="9" x2="15" y2="15" />
        </svg>
        <svg
          v-else
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <circle cx="12" cy="12" r="10" />
          <line x1="12" y1="8" x2="12" y2="12" />
          <line x1="12" y1="16" x2="12" y2="16" />
        </svg>
      </span>
      <span class="toast-text">{{ toast.msg }}</span>
    </div>
  </transition>
</template>

<script setup lang="ts">
defineProps<{ toast: { visible: boolean; msg: string; variant?: string } }>()
</script>

<style scoped>
.dnd-toast {
  position: fixed;
  right: 1.5rem;
  bottom: 1.5rem;
  display: inline-flex;
  gap: 0.6rem;
  align-items: center;
  background: rgba(10, 10, 10, 0.9);
  color: white;
  padding: 0.6rem 0.9rem;
  border-radius: 8px;
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.4);
  font-weight: 600;
  z-index: 60;
}
.dnd-toast .toast-icon svg {
  display: block;
}
.dnd-toast.variant-success {
  background: linear-gradient(90deg, #1f8a3e, #2fbf6f);
}
.dnd-toast.variant-info {
  background: linear-gradient(90deg, #2b6fb3, #4da6ff);
}
.dnd-toast.variant-error {
  background: linear-gradient(90deg, #b33a2a, #ff6b5a);
}
.toast-text {
  color: white;
}
.toast-fade-enter-from,
.toast-fade-leave-to {
  opacity: 0;
  transform: translateY(8px) scale(0.98);
}
.toast-fade-enter-active,
.toast-fade-leave-active {
  transition: all 220ms cubic-bezier(0.2, 0.9, 0.3, 1);
}
</style>
