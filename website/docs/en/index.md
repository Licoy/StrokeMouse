---
layout: home
title: "StrokeMouse"
titleTemplate: "Mouse gestures for macOS"
description: "StrokeMouse is a macOS mouse gesture tool. Hold a trigger, draw a stroke, run shortcuts and scripts. App-scoped gestures, JSON import/export, menu-bar resident."
---

<div class="sm-home">

<GeekHero
  title="Drive macOS with mouse strokes"
  tagline="Hold a trigger, draw a stroke, run shortcuts, window actions, or scripts."
  primary-text="Download"
  primary-link="/en/download"
  secondary-text="Read the docs"
  secondary-link="/en/guide/getting-started"
  image-src="/screenshots/1.png"
  image-alt="Gesture library"
  hud-label="Stroke capture"
/>

<ProofStrip
  :items="['Local-first', 'No telemetry', 'Open source AGPL', 'macOS 14+']"
/>

<HowItWorks
  heading="Your first gesture in three steps"
  :steps="[
    { title: 'Download', desc: 'Install the Apple Silicon or Intel build.' },
    { title: 'Grant access', desc: 'Enable Accessibility in System Settings.' },
    { title: 'Draw', desc: 'Hold right-click and stroke up for Mission Control.' },
  ]"
/>

<FeatureBento
  heading="Built for power users"
  lead="Menu-bar resident, controllable matching, actions from shortcuts to scripts."
  :items="[
    { icon: 'sparkles', title: 'Free-path matching', desc: 'Normalize, limited rotation, and structure gates that reject sloppy near-misses.', size: 'large', image: '/screenshots/5.png', imageAlt: 'Record stroke' },
    { icon: 'menu', title: 'Menu bar resident', desc: 'Start or stop gestures, open settings; icon tints when paused or untrusted.' },
    { icon: 'mouse', title: 'Per-gesture triggers', desc: 'Default right button; middle or side allowed. Only enabled triggers are watched.' },
    { title: 'General settings', desc: 'Match threshold, appearance, and engine options.', size: 'media', image: '/screenshots/3.png', imageAlt: 'General settings' },
    { icon: 'window', title: 'App scope', desc: 'Global or per-app matching; sidebar groups by scope.' },
    { icon: 'zap', title: 'Actions and import', desc: 'Shortcuts, windows, media, Shell and AppleScript; JSON batch tools.' },
  ]"
/>

<GestureTiles
  heading="Default gestures"
  lead="Useful strokes out of the box, fully customizable."
/>

<ScreenshotCarousel
  heading="Product screens"
  description="Gesture library, testing, settings, and permissions."
  :shots="[
    { src: '/screenshots/1.png', alt: 'Gesture list' },
    { src: '/screenshots/2.png', alt: 'Gesture test' },
    { src: '/screenshots/3.png', alt: 'General settings' },
    { src: '/screenshots/4.png', alt: 'Permissions' },
    { src: '/screenshots/5.png', alt: 'Record stroke' },
    { src: '/screenshots/6.png', alt: 'App scope' },
  ]"
/>

<HomeCta
  heading="Get StrokeMouse"
  lead="Runs locally. Configs import and export as JSON."
  :steps="['Download the build for your chip', 'Grant Accessibility', 'Draw your first stroke']"
  primary-text="Download"
  primary-link="/en/download"
  secondary-text="Read the docs"
  secondary-link="/en/guide/getting-started"
/>

</div>
