import type { DefaultTheme, HeadConfig, UserConfig } from 'vitepress'
import {
  absoluteUrl,
  alternatePath,
  DEFAULT_OG_IMAGE,
  pathFromRelative,
  resolvePageSeo,
  SITE_NAME,
  SITE_TITLE,
  SITE_URL,
} from './seo'

export { SITE_TITLE, SITE_URL }
export const GITHUB_URL = 'https://github.com/Licoy/StrokeMouse'

export const sharedHead: HeadConfig[] = [
  ['link', { rel: 'icon', type: 'image/png', href: '/favicon.png' }],
  ['link', { rel: 'apple-touch-icon', href: '/favicon.png' }],
  ['meta', { name: 'theme-color', content: '#0a0e14' }],
  ['meta', { name: 'author', content: 'StrokeMouse' }],
  ['meta', { name: 'robots', content: 'index, follow, max-image-preview:large' }],
  ['meta', { name: 'googlebot', content: 'index, follow' }],
  ['meta', { name: 'format-detection', content: 'telephone=no' }],
  [
    'meta',
    {
      name: 'viewport',
      content: 'width=device-width,initial-scale=1',
    },
  ],
  // Default social (per-page overrides via transformHead)
  ['meta', { property: 'og:site_name', content: SITE_NAME }],
  ['meta', { property: 'og:type', content: 'website' }],
  ['meta', { property: 'og:image', content: DEFAULT_OG_IMAGE }],
  ['meta', { property: 'og:image:alt', content: 'StrokeMouse' }],
  ['meta', { name: 'twitter:card', content: 'summary' }],
  ['meta', { name: 'twitter:image', content: DEFAULT_OG_IMAGE }],
]

export const socialLinks: DefaultTheme.SocialLink[] = [
  { icon: 'github', link: GITHUB_URL },
]

export const sharedConfig: UserConfig = {
  title: SITE_TITLE,
  cleanUrls: true,
  lastUpdated: true,
  ignoreDeadLinks: false,
  appearance: 'dark',
  head: sharedHead,

  // Fill title / description for every page from the SEO registry
  transformPageData(pageData) {
    const seo = resolvePageSeo(pageData.relativePath)
    const isHome =
      pageData.relativePath === 'index.md' || pageData.relativePath === 'en/index.md'
    const isEn = pageData.relativePath.replace(/\\/g, '/').startsWith('en/')

    pageData.description = seo.description
    // Force full <title> so search engines never see bare H1-only titles
    if (isHome) {
      pageData.title = seo.title
      pageData.frontmatter = {
        ...pageData.frontmatter,
        title: seo.title,
        description: seo.description,
        titleTemplate: isEn ? 'Mouse gestures for macOS' : 'macOS 鼠标手势',
      }
    } else {
      const full = `${seo.title} | ${SITE_TITLE}`
      pageData.title = full
      pageData.frontmatter = {
        ...pageData.frontmatter,
        title: full,
        description: seo.description,
        titleTemplate: false,
      }
    }
  },

  // Inject full SEO head tags on every built page
  transformHead({ pageData }) {
    const seo = resolvePageSeo(pageData.relativePath)
    const pathname = pathFromRelative(pageData.relativePath)
    const pathForCanon =
      pathname === '/en' || pathname === '/en/' ? '/en/' : pathname === '/' ? '/' : pathname
    const canonical = absoluteUrl(pathForCanon)
    const alts = alternatePath(pathname)
    const enCanonical =
      alts.en === '/en' || alts.en === '/en/' ? absoluteUrl('/en/') : absoluteUrl(alts.en)
    const zhCanonical = alts.zh === '/' ? absoluteUrl('/') : absoluteUrl(alts.zh)

    const isEn = pageData.relativePath.replace(/\\/g, '/').startsWith('en/')
    const locale = isEn ? 'en_US' : 'zh_CN'
    const fullTitle =
      seo.title === SITE_TITLE ? `${SITE_TITLE} — ${isEn ? 'Mouse gestures for macOS' : 'macOS 鼠标手势'}` : `${seo.title} | ${SITE_TITLE}`

    const tags: HeadConfig[] = [
      ['meta', { name: 'description', content: seo.description }],
      ['meta', { name: 'keywords', content: seo.keywords }],
      ['link', { rel: 'canonical', href: canonical }],

      // hreflang for bilingual SEO
      ['link', { rel: 'alternate', hreflang: 'zh-CN', href: zhCanonical }],
      ['link', { rel: 'alternate', hreflang: 'en-US', href: enCanonical }],
      ['link', { rel: 'alternate', hreflang: 'x-default', href: zhCanonical }],

      // Open Graph
      ['meta', { property: 'og:title', content: fullTitle }],
      ['meta', { property: 'og:description', content: seo.description }],
      ['meta', { property: 'og:url', content: canonical }],
      ['meta', { property: 'og:type', content: seo.ogType ?? 'website' }],
      ['meta', { property: 'og:locale', content: locale }],
      [
        'meta',
        {
          property: 'og:locale:alternate',
          content: isEn ? 'zh_CN' : 'en_US',
        },
      ],
      ['meta', { property: 'og:site_name', content: SITE_NAME }],
      ['meta', { property: 'og:image', content: DEFAULT_OG_IMAGE }],
      ['meta', { property: 'og:image:alt', content: fullTitle }],

      // Twitter
      ['meta', { name: 'twitter:card', content: 'summary' }],
      ['meta', { name: 'twitter:title', content: fullTitle }],
      ['meta', { name: 'twitter:description', content: seo.description }],
      ['meta', { name: 'twitter:image', content: DEFAULT_OG_IMAGE }],
    ]

    // JSON-LD structured data
    const webPageLd = {
      '@context': 'https://schema.org',
      '@type': pathname === '/' || pathname === '/en' || pathname === '/en/' ? 'WebSite' : 'WebPage',
      name: fullTitle,
      description: seo.description,
      url: canonical,
      inLanguage: isEn ? 'en-US' : 'zh-CN',
      isPartOf: {
        '@type': 'WebSite',
        name: SITE_NAME,
        url: SITE_URL,
      },
    }

    tags.push(['script', { type: 'application/ld+json' }, JSON.stringify(webPageLd)])

    // SoftwareApplication on home + download
    if (
      pathname === '/' ||
      pathname === '/en' ||
      pathname === '/en/' ||
      pathname === '/download' ||
      pathname === '/en/download'
    ) {
      const appLd = {
        '@context': 'https://schema.org',
        '@type': 'SoftwareApplication',
        name: 'StrokeMouse',
        applicationCategory: 'UtilitiesApplication',
        operatingSystem: 'macOS 14 or later',
        description: seo.description,
        url: absoluteUrl(pathname === '/en' || pathname === '/en/' || pathname.startsWith('/en') ? '/en/' : '/'),
        downloadUrl: absoluteUrl(isEn ? '/en/download' : '/download'),
        image: DEFAULT_OG_IMAGE,
        offers: {
          '@type': 'Offer',
          price: '0',
          priceCurrency: 'USD',
        },
      }
      tags.push(['script', { type: 'application/ld+json' }, JSON.stringify(appLd)])
    }

    // FAQPage for FAQ routes
    if (pathname.endsWith('/guide/faq')) {
      const faqLd = isEn
        ? {
            '@context': 'https://schema.org',
            '@type': 'FAQPage',
            mainEntity: [
              {
                '@type': 'Question',
                name: 'Gestures do nothing?',
                acceptedAnswer: {
                  '@type': 'Answer',
                  text: 'Check Accessibility for this app, menu bar status, that the gesture is enabled, you hold the configured trigger, and the stroke is long enough.',
                },
              },
              {
                '@type': 'Question',
                name: 'Right-click menu gone?',
                acceptedAnswer: {
                  '@type': 'Answer',
                  text: 'A short right-click still opens the menu. Long strokes are gesture-only. Or bind gestures to middle/side buttons.',
                },
              },
            ],
          }
        : {
            '@context': 'https://schema.org',
            '@type': 'FAQPage',
            mainEntity: [
              {
                '@type': 'Question',
                name: '手势完全没反应？',
                acceptedAnswer: {
                  '@type': 'Answer',
                  text: '请检查辅助功能是否授权当前 App、菜单栏状态、手势是否启用、是否按住正确触发键，以及滑动是否足够长。',
                },
              },
              {
                '@type': 'Question',
                name: '右键菜单没了？',
                acceptedAnswer: {
                  '@type': 'Answer',
                  text: '短按右键仍可弹出菜单；长距离滑动仅用于手势。也可把手势改到中键/侧键。',
                },
              },
            ],
          }
      tags.push(['script', { type: 'application/ld+json' }, JSON.stringify(faqLd)])
    }

    return tags
  },

  // Build-time sitemap.xml covering all locales (/, /en/, guide pages, download, …)
  sitemap: {
    hostname: SITE_URL,
    transformItems(items) {
      return items.map((item) => {
        const path = `/${item.url}`.replace(/\/{2,}/g, '/').replace(/\/$/, '') || '/'
        const isHome = path === '/' || path === '/en'
        const isDownload = path.endsWith('/download') || path === '/download'
        const isQuickStart = path.includes('/guide/getting-started')
        return {
          ...item,
          changefreq: isHome ? ('weekly' as const) : ('monthly' as const),
          priority: isHome ? 1.0 : isDownload ? 0.9 : isQuickStart ? 0.85 : 0.7,
        }
      })
    },
  },
  markdown: {
    theme: {
      light: 'github-light',
      dark: 'github-dark',
    },
    lineNumbers: false,
  },
  themeConfig: {
    logo: { src: '/logo.svg', alt: 'StrokeMouse' },
    socialLinks,
    outline: { level: [2, 3] },
    externalLinkIcon: true,
    search: {
      provider: 'local',
      options: {
        locales: {
          root: {
            translations: {
              button: {
                buttonText: '搜索',
                buttonAriaLabel: '搜索文档',
              },
              modal: {
                displayDetails: '显示详情',
                resetButtonTitle: '清除查询',
                backButtonTitle: '返回',
                noResultsText: '没有找到结果',
                footer: {
                  selectText: '选择',
                  navigateText: '切换',
                  closeText: '关闭',
                },
              },
            },
          },
          en: {
            translations: {
              button: {
                buttonText: 'Search',
                buttonAriaLabel: 'Search docs',
              },
              modal: {
                displayDetails: 'Display details',
                resetButtonTitle: 'Reset search',
                backButtonTitle: 'Back',
                noResultsText: 'No results',
                footer: {
                  selectText: 'to select',
                  navigateText: 'to navigate',
                  closeText: 'to close',
                },
              },
            },
          },
        },
      },
    },
  },
}
