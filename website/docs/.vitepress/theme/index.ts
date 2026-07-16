import type { Theme } from 'vitepress'
import DefaultTheme from 'vitepress/theme'
import Layout from './Layout.vue'
import GeekHero from './components/GeekHero.vue'
import FeatureGrid from './components/FeatureGrid.vue'
import TerminalBlock from './components/TerminalBlock.vue'
import GestureTable from './components/GestureTable.vue'
import CalloutBanner from './components/CalloutBanner.vue'
import DownloadPage from './components/DownloadPage.vue'
import DefaultGestures from './components/DefaultGestures.vue'
import './style.css'

export default {
  extends: DefaultTheme,
  Layout,
  enhanceApp({ app }) {
    app.component('GeekHero', GeekHero)
    app.component('FeatureGrid', FeatureGrid)
    app.component('TerminalBlock', TerminalBlock)
    app.component('GestureTable', GestureTable)
    app.component('CalloutBanner', CalloutBanner)
    app.component('DownloadPage', DownloadPage)
    app.component('DefaultGestures', DefaultGestures)
  },
} satisfies Theme
