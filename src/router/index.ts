import { createRouter, createWebHistory } from 'vue-router'
import LandingView from '../views/LandingView.vue'
import LoginView from '@/views/LoginView.vue'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'

declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean
    requiresCampaign?: boolean
    requiresOwner?: boolean
    guestOnly?: boolean
  }
}

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: LandingView,
    },
    {
      path: '/login',
      name: 'login',
      component: LoginView,
      meta: { guestOnly: true },
    },
    {
      path: '/reset-password',
      name: 'reset-password',
      component: () => import('@/views/ResetPasswordView.vue'),
    },
    {
      path: '/campaigns',
      name: 'campaigns',
      component: () => import('@/views/CampaignsView.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/campaigns/:id',
      name: 'campaign-detail',
      component: () => import('@/views/CampaignDetailView.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/join/:code',
      name: 'join-campaign',
      component: () => import('@/views/JoinCampaignView.vue'),
      meta: { requiresAuth: true },
    },
    {
      path: '/notes',
      name: 'notes',
      component: () => import('@/views/NotesView.vue'),
      meta: { requiresAuth: true, requiresCampaign: true },
    },
    {
      path: '/links',
      name: 'links',
      component: () => import('@/views/LinksView.vue'),
      meta: { requiresAuth: true, requiresCampaign: true },
    },
    {
      path: '/characters',
      name: 'about',
      component: () => import('@/views/AboutView.vue'),
      meta: { requiresAuth: true, requiresCampaign: true },
    },
    {
      path: '/healer',
      name: 'healer',
      component: () => import('@/views/HealerView.vue'),
      meta: { requiresAuth: true, requiresCampaign: true },
    },
    {
      path: '/dm',
      name: 'dm-workspace',
      component: () => import('@/views/DmWorkspaceView.vue'),
      meta: { requiresAuth: true, requiresCampaign: true, requiresOwner: true },
    },
  ],
})

const AUTH_READY_MS = 12_000

function waitForAuthReady(auth: ReturnType<typeof useAuthStore>) {
  if (!auth.loading) return Promise.resolve()

  return Promise.race([
    new Promise<void>((resolve) => {
      const stop = auth.$subscribe(() => {
        if (!auth.loading) {
          stop()
          resolve()
        }
      })
      if (!auth.loading) {
        stop()
        resolve()
      }
    }),
    new Promise<void>((resolve) => setTimeout(resolve, AUTH_READY_MS)),
  ])
}

router.beforeEach(async (to) => {
  // Root query links load directly on GitHub Pages, including a fresh visit.
  if (to.name === 'home' && typeof to.query.recap === 'string') return true
  const auth = useAuthStore()

  await waitForAuthReady(auth)

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  if (to.meta.guestOnly && auth.isAuthenticated) {
    return { name: 'home' }
  }

  if (to.meta.requiresCampaign && auth.isAuthenticated) {
    const campaignStore = useCampaignStore()
    if (campaignStore.campaigns.length === 0) {
      await campaignStore.fetchCampaigns()
    }
    if (!campaignStore.activeCampaignId) {
      if (!campaignStore.activeCampaignId) {
        return { name: 'campaigns' }
      }
    }

    if (to.meta.requiresOwner) {
      const activeCampaign = campaignStore.activeCampaign
      if (!activeCampaign || activeCampaign.created_by !== auth.user?.id) {
        return { name: 'home' }
      }
    }
  }
})

export default router
