import { reactive } from 'vue'

export type ToastVariant = 'success' | 'info' | 'error'
type ToastState = { msg: string; visible: boolean; variant?: ToastVariant }

const state = reactive<ToastState>({ msg: '', visible: false, variant: 'info' })
let timer: number | undefined

export function showToast(msg: string, variant: ToastVariant = 'info', ms = 2200) {
  state.msg = msg
  state.variant = variant
  state.visible = true
  if (timer) window.clearTimeout(timer)
  timer = window.setTimeout(() => (state.visible = false), ms)
}

export function getToastState() {
  return state
}

export function clearToastTimer() {
  if (timer) {
    window.clearTimeout(timer)
    timer = undefined
  }
}
