<template>
  <transition name="toast-fade">
    <div v-if="toast.visible" class="dnd-toast" role="status" aria-live="polite">
      {{ toast.msg }}
    </div>
  </transition>
</template>

<script setup lang="ts">
// using defineProps only; keep component as multi-word via defineOptions for linter
defineProps<{ toast: { visible: boolean; msg: string } }>()
// lightweight presentational component
</script>

<style scoped>
.dnd-toast {
  position: fixed;
  right: 1.5rem;
  bottom: 1.5rem;
  background: rgba(10, 10, 10, 0.9);
  color: white;
  padding: 0.6rem 0.9rem;
  border-radius: 8px;
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.4);
  font-weight: 600;
  z-index: 60;
}
.toast-fade-enter-from,
.toast-fade-leave-to {
  opacity: 0;
  transform: translateY(6px) scale(0.98);
}
.toast-fade-enter-active,
.toast-fade-leave-active {
  transition: all 220ms cubic-bezier(0.2, 0.9, 0.3, 1);
}
</style>
