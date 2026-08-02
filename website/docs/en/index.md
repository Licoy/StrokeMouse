---
layout: home
title: "StrokeMouse"
titleTemplate: "Mouse & trackpad gestures for macOS"
description: "StrokeMouse is a macOS mouse and trackpad gesture tool. Draw with a mouse button or one modifier key, or use experimental multi-touch gestures, then run shortcuts, window actions, and scripts."
---

<div class="sm-home">

<GeekHero
  title="Drive macOS with mouse and trackpad gestures"
  tagline="Draw with a mouse button or one modifier key, or use experimental multi-touch gestures, then run shortcuts, window actions, or scripts."
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
    { title: 'Choose an input', desc: 'Mouse Draw, Trackpad Draw, or Touch Gestures.' },
  ]"
/>

<FeatureBento
  heading="Built for power users"
  lead="Three input modes share actions and app scope; drawn paths use controllable matching."
  :items="[
    { icon: 'sparkles', title: 'Free-path matching', desc: 'Normalize, limited rotation, and structure gates that reject sloppy near-misses.', size: 'large', image: '/screenshots/5.png', imageAlt: 'Record stroke' },
    { icon: 'menu', title: 'Menu bar resident', desc: 'Start or stop gestures, open settings; icon tints when paused or untrusted.' },
    { icon: 'mouse', title: 'Mouse Draw', desc: 'Trigger with the right, middle, or a side button; only enabled buttons are watched.' },
    { icon: 'sparkles', title: 'Trackpad Draw', desc: 'Hold one Fn, Control, Option, Shift, or Command and move the pointer; reuse a mouse-draw rule when you want.' },
    { icon: 'zap', title: 'Experimental Touch Gestures', desc: '34 multi-finger taps, swipes, pinches, spreads, and rotations; macOS gestures may also run.' },
    { title: 'General settings', desc: 'Match threshold, appearance, and the Touch Gestures master switch.', size: 'media', image: '/screenshots/3.png', imageAlt: 'General settings' },
    { icon: 'window', title: 'App scope', desc: 'Global or per-app matching; sidebar groups by scope.' },
    { icon: 'import', title: 'Actions and import', desc: 'Shortcuts, windows, media, Shell and AppleScript; JSON batch tools.' },
  ]"
/>

<GestureTiles
  heading="Default mouse-draw gestures"
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
  lead="Runs locally. All three input modes share actions and app scope; configs import and export as JSON."
  :steps="['Download the build for your chip', 'Grant Accessibility', 'Choose an input and configure your first gesture']"
  primary-text="Download"
  primary-link="/en/download"
  secondary-text="Read the docs"
  secondary-link="/en/guide/getting-started"
/>

</div>
