---
layout: home
title: "StrokeMouse"
titleTemplate: "Gestes souris et trackpad pour macOS"
description: "StrokeMouse est un outil de gestes souris et trackpad pour macOS. Dessinez avec un bouton ou une touche de modification, ou utilisez le multitouch expérimental, puis lancez raccourcis, fenêtres et scripts. Inversez chaque axe de défilement et lissez une molette crantée."
---

<div class="sm-home">

<GeekHero
  title="Pilotez macOS avec des gestes souris et trackpad"
  tagline="Dessinez en maintenant un bouton de souris ou une seule touche de modification, ou utilisez des gestes tactiles expérimentaux. En cas de correspondance, l’app lance raccourcis, actions de fenêtre ou scripts."
  primary-text="Télécharger"
  primary-link="/fr/download"
  secondary-text="Lire la documentation"
  secondary-link="/fr/guide/getting-started"
  image-src="/screenshots/1.png"
  image-alt="Liste des gestes"
  hud-label="Capture du trait"
/>

<ProofStrip
  :items="['Exécution locale', 'Sans télémétrie', 'Open source AGPL', 'macOS 14+']"
/>

<PromoVideo
  heading="StrokeMouse en deux minutes"
  description="Modes de saisie, actions, fonctionnement de la reconnaissance et prise en main en trois étapes. Texte à l’écran en chinois simplifié."
  play-label="Lire la vidéo"
/>

<ScreenshotCarousel
  heading="Écrans du produit"
  description="Bibliothèque de gestes, test, réglages et autorisations."
  :shots="[
    { src: '/screenshots/1.png', alt: 'Liste des gestes' },
    { src: '/screenshots/2.png', alt: 'Test de geste' },
    { src: '/screenshots/3.png', alt: 'Réglages généraux' },
    { src: '/screenshots/4.png', alt: 'Autorisations' },
    { src: '/screenshots/5.png', alt: 'Enregistrement du trait' },
    { src: '/screenshots/6.png', alt: 'Portée d’application' },
  ]"
/>

<HowItWorks
  heading="Votre premier geste en trois étapes"
  :steps="[
    { title: 'Télécharger', desc: 'Installez la version Apple Silicon ou Intel.' },
    { title: 'Autoriser', desc: 'Activez l’Accessibilité dans Réglages Système.' },
    { title: 'Choisir une entrée', desc: 'Dessin souris, dessin trackpad ou gestes tactiles.' },
  ]"
/>

<FeatureBento
  heading="Conçu pour les utilisateurs avancés"
  lead="Trois modes d’entrée partagent actions et portée d’app ; les trajectoires dessinées utilisent une correspondance contrôlable. Le défilement amélioré se règle à part et reste sur ce Mac."
  :items="[
    { icon: 'sparkles', title: 'Correspondance libre', desc: 'Normalisation, rotation limitée et portes structurelles qui rejettent les presque-correspondances approximatives.', size: 'large', image: '/screenshots/5.png', imageAlt: 'Enregistrement du trait' },
    { icon: 'menu', title: 'Toujours dans la barre des menus', desc: 'Démarrez ou arrêtez les gestes, ouvrez les réglages ; l’icône change de teinte en pause ou sans autorisation.' },
    { icon: 'mouse', title: 'Dessin souris', desc: 'Déclenchez avec le bouton droit, du milieu ou un bouton latéral ; seuls les boutons activés sont surveillés.' },
    { icon: 'sparkles', title: 'Dessin trackpad', desc: 'Maintenez Fn, Control, Option, Shift ou Command et déplacez le pointeur ; réutilisez une règle de dessin souris si vous voulez.' },
    { icon: 'zap', title: 'Gestes tactiles expérimentaux', desc: '34 classes de tapotements, balayages, pincements, écartements et rotations ; les gestes système peuvent aussi se produire.' },
    { icon: 'mouse', title: 'Défilement amélioré', desc: 'Inversez la molette et le trackpad par axe, et lissez une molette crantée. Absent de la sauvegarde des gestes.', href: '/guide/settings#scroll-enhancement' },
    { title: 'Réglages généraux', desc: 'Seuil de correspondance, apparence et interrupteur général des gestes tactiles.', size: 'media', image: '/screenshots/3.png', imageAlt: 'Réglages généraux' },
    { icon: 'window', title: 'Portée d’app', desc: 'Globale ou par application ; la barre latérale groupe les gestes par portée.' },
    { icon: 'import', title: 'Actions et import', desc: 'Raccourcis, fenêtres, média, Shell et AppleScript ; gestion par lots en JSON.' },
  ]"
/>

<GestureTiles
  heading="Gestes souris par défaut"
  lead="Des traits utiles dès l’installation, entièrement personnalisables."
/>

<HomeCta
  heading="Commencer avec StrokeMouse"
  lead="S’exécute en local. Les trois modes d’entrée partagent actions et portée d’app ; les configs s’importent et s’exportent en JSON."
  :steps="['Téléchargez la version pour votre puce', 'Accordez l’Accessibilité', 'Choisissez une entrée et configurez votre premier geste']"
  primary-text="Télécharger"
  primary-link="/fr/download"
  secondary-text="Lire la documentation"
  secondary-link="/fr/guide/getting-started"
/>

</div>
