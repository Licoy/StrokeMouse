import { onMounted, onUnmounted, type Ref } from 'vue'

/** IntersectionObserver scroll-reveal (no window scroll listeners). */
export function useReveal(root: Ref<HTMLElement | null>, threshold = 0.12) {
  let observer: IntersectionObserver | null = null

  onMounted(() => {
    const el = root.value
    if (!el) return

    // Enable motion-only hide class after mount (avoids FOUC of invisible content)
    document.documentElement.classList.add('sm-motion')

    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      el.classList.add('is-visible')
      el.querySelectorAll('.sm-reveal').forEach((t) => t.classList.add('is-visible'))
      return
    }

    observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible')
            observer?.unobserve(entry.target)
          }
        }
      },
      { threshold, rootMargin: '0px 0px -4% 0px' },
    )

    const targets = el.querySelectorAll('.sm-reveal')
    if (targets.length === 0) {
      el.classList.add('sm-reveal')
      observer.observe(el)
    } else {
      targets.forEach((t) => observer!.observe(t))
    }
  })

  onUnmounted(() => {
    observer?.disconnect()
  })
}
