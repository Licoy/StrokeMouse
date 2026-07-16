<script setup lang="ts">
import DefaultTheme from 'vitepress/theme'
import SiteFooter from './components/SiteFooter.vue'

const { Layout } = DefaultTheme
</script>

<template>
  <Layout>
    <template #layout-top>
      <div class="sm-backdrop" aria-hidden="true">
        <div class="sm-backdrop__grid" />
        <div class="sm-backdrop__grid-lg" />
        <div class="sm-backdrop__vignette" />
      </div>
    </template>
    <template #layout-bottom>
      <SiteFooter />
    </template>
  </Layout>
</template>
