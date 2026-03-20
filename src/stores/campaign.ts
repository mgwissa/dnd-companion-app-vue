import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from './auth'

export interface Campaign {
  id: string
  name: string
  invite_code: string
  created_by: string | null
  created_at: string
  updated_at: string
}

export interface CampaignMember {
  id: string
  campaign_id: string
  user_id: string
  role: 'owner' | 'member'
  joined_at: string
  email?: string
  display_name?: string
}

const ACTIVE_KEY = 'dnd_active_campaign'

export const useCampaignStore = defineStore('campaign', () => {
  const campaigns = ref<Campaign[]>([])
  const members = ref<CampaignMember[]>([])
  const activeCampaignId = ref<string | null>(localStorage.getItem(ACTIVE_KEY))
  const loading = ref(false)

  const activeCampaign = computed(
    () => campaigns.value.find((c) => c.id === activeCampaignId.value) ?? null,
  )

  const myRole = computed(() => {
    const auth = useAuthStore()
    if (!activeCampaignId.value || !auth.user) return null
    return members.value.find((m) => m.user_id === auth.user!.id)?.role ?? null
  })

  const isOwner = computed(() => myRole.value === 'owner')

  function setActiveCampaign(id: string | null) {
    activeCampaignId.value = id
    if (id) localStorage.setItem(ACTIVE_KEY, id)
    else localStorage.removeItem(ACTIVE_KEY)
    members.value = []
  }

  async function fetchCampaigns() {
    loading.value = true
    try {
      const { data, error } = await supabase
        .from('campaigns')
        .select('*')
        .order('created_at', { ascending: false })
      if (error) throw error
      campaigns.value = data as Campaign[]

      if (activeCampaignId.value && !campaigns.value.find((c) => c.id === activeCampaignId.value)) {
        setActiveCampaign(campaigns.value[0]?.id ?? null)
      }
    } finally {
      loading.value = false
    }
  }

  async function createCampaign(name: string) {
    const { data, error } = await supabase.rpc('create_campaign', { campaign_name: name })
    if (error) throw error

    const campaign = data as Campaign
    campaigns.value.unshift(campaign)
    setActiveCampaign(campaign.id)
    return campaign
  }

  async function joinCampaign(code: string) {
    const { data, error } = await supabase.rpc('join_campaign', { code })
    if (error) throw error

    const result = data as { id: string; name: string; already_member: boolean }
    if (!result.already_member) {
      await fetchCampaigns()
    }
    setActiveCampaign(result.id)
    return result
  }

  async function fetchMembers(campaignId: string) {
    const { data, error } = await supabase
      .from('campaign_members')
      .select('*')
      .eq('campaign_id', campaignId)
      .order('joined_at')
    if (error) throw error
    members.value = data as CampaignMember[]
  }

  async function removeMember(memberId: string) {
    const { error } = await supabase.from('campaign_members').delete().eq('id', memberId)
    if (error) throw error
    members.value = members.value.filter((m) => m.id !== memberId)
  }

  async function deleteCampaign(campaignId: string) {
    const { error } = await supabase.from('campaigns').delete().eq('id', campaignId)
    if (error) throw error

    campaigns.value = campaigns.value.filter((c) => c.id !== campaignId)
    if (activeCampaignId.value === campaignId) {
      setActiveCampaign(campaigns.value[0]?.id ?? null)
    }
  }

  async function leaveCampaign(campaignId: string) {
    const auth = useAuthStore()
    const { error } = await supabase
      .from('campaign_members')
      .delete()
      .eq('campaign_id', campaignId)
      .eq('user_id', auth.user!.id)
    if (error) throw error

    campaigns.value = campaigns.value.filter((c) => c.id !== campaignId)
    if (activeCampaignId.value === campaignId) {
      setActiveCampaign(campaigns.value[0]?.id ?? null)
    }
  }

  function reset() {
    campaigns.value = []
    members.value = []
    setActiveCampaign(null)
  }

  return {
    campaigns,
    members,
    activeCampaignId,
    activeCampaign,
    myRole,
    isOwner,
    loading,
    setActiveCampaign,
    fetchCampaigns,
    createCampaign,
    joinCampaign,
    fetchMembers,
    removeMember,
    deleteCampaign,
    leaveCampaign,
    reset,
  }
})
