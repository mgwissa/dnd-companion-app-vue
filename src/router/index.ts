import { createRouter, createWebHistory } from 'vue-router'
import HomeView from '../views/HomeView.vue'
import LoginView from '@/views/LoginView.vue'
import { useAuthStore } from '@/stores/auth'
import { useCampaignStore } from '@/stores/campaign'

declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean
    requiresCampaign?: boolean
    guestOnly?: boolean
  }
}

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: HomeView,
    },
    {
      path: '/login',
      name: 'login',
      component: LoginView,
      meta: { guestOnly: true },
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
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (auth.loading) {
    await new Promise<void>((resolve) => {
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
    })
  }

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  if (to.meta.guestOnly && auth.isAuthenticated) {
    return { name: 'home' }
  }

  if (to.meta.requiresCampaign && auth.isAuthenticated) {
    const campaignStore = useCampaignStore()
    if (!campaignStore.activeCampaignId) {
      if (campaignStore.campaigns.length === 0) {
        await campaignStore.fetchCampaigns()
      }
      if (!campaignStore.activeCampaignId) {
        return { name: 'campaigns' }
      }
    }
  }
})

export default router
