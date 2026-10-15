<script setup lang="ts">
import { useRoute } from 'vue-router'
import HomeView from './HomeView.vue'
import SharedRecapView from './SharedRecapView.vue'
const route = useRoute()
</script>

<template>
  <SharedRecapView v-if="typeof route.query.recap === 'string'" :token="route.query.recap" />
  <HomeView v-else />
</template>
