---
layout: home
title: "StrokeMouse"
titleTemplate: "Mouse gestures for macOS"
description: "StrokeMouse is a macOS mouse gesture tool. Hold a trigger, draw a stroke, run shortcuts and scripts. App-scoped gestures, JSON import/export, menu-bar resident."
---

<div class="sm-home">

<GeekHero
  title="StrokeMouse"
  title-accent="Draw. Match. Act."
  tagline="Hold a trigger button, draw a stroke, and run shortcuts, apps, window actions, media keys, or Shell / AppleScript. Import and export configs, pick app scopes visually. Local-first, menu-bar resident—no remote telemetry or data collection."
  primary-text="Download"
  primary-link="/en/download"
  secondary-text="Read the docs"
  secondary-link="/en/guide/getting-started"
  hud-label="stroke capture · live"
/>

<TerminalBlock
  title="quickstart"
  :lines="[
    'open StrokeMouse.app',
    '# Settings → Permissions → enable Accessibility',
    '# Hold right button, stroke upward, release',
    '# → Mission Control',
  ]"
/>

<ScreenshotCarousel
  heading="Screenshots"
  description="Gesture library, testing, settings, and permissions — what you see is what you get."
  frame-tag="Preview"
  :shots="[
    { src: '/screenshots/1.png', alt: 'Gesture list' },
    { src: '/screenshots/2.png', alt: 'Gesture test' },
    { src: '/screenshots/3.png', alt: 'General settings' },
    { src: '/screenshots/4.png', alt: 'Permissions' },
    { src: '/screenshots/5.png', alt: 'Record stroke' },
    { src: '/screenshots/6.png', alt: 'App scope' },
  ]"
/>

<FeatureGrid
  subheading="Capabilities"
  heading="Built for power users"
  :items="[
    { icon: 'menu', title: 'Menu bar resident', desc: 'Start/stop gestures, open settings, see permission status, quit — all from the menu bar.' },
    { icon: 'sparkles', title: 'Free-path matching', desc: 'Normalize + limited rotation + structure gates that reject sloppy near-misses.' },
    { icon: 'mouse', title: 'Per-gesture triggers', desc: 'Default right button; middle or side buttons allowed. Only enabled triggers are monitored.' },
    { icon: 'window', title: 'Visual app scope', desc: 'Global, or multi-select installed apps by icon. Match only when those apps are frontmost.' },
    { icon: 'zap', title: 'Rich actions', desc: 'Shortcuts, open app, URL, media keys, window ops, Shell, AppleScript.' },
    { icon: 'import', title: 'Import, export & batch', desc: 'Search, filter, multi-select batch toggles; JSON packages with skip-or-force duplicate handling.' },
  ]"
/>

<DefaultGestures subheading="Defaults" heading="Default gestures" />

<section class="sm-cta">
  <p class="sm-cta__kicker">Get started now</p>
  <h2 class="sm-cta__title">Three steps to your first gesture</h2>
  <ol class="sm-cta__steps">
    <li>
      <span class="sm-cta__num">1</span>
      <span class="sm-cta__text"><strong>Download</strong> — pick Apple Silicon or Intel</span>
    </li>
    <li>
      <span class="sm-cta__num">2</span>
      <span class="sm-cta__text"><strong>Grant Accessibility</strong> — Settings → Permissions</span>
    </li>
    <li>
      <span class="sm-cta__num">3</span>
      <span class="sm-cta__text"><strong>Draw a stroke</strong> — hold right-click, swipe up for Mission Control</span>
    </li>
  </ol>
  <div class="sm-cta__actions">
    <a class="sm-btn sm-btn--primary" href="/en/download">Download now</a>
    <a class="sm-btn sm-btn--ghost" href="/en/guide/getting-started">Quick start guide</a>
  </div>
</section>

</div>
