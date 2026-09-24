---
title: "Démarrage rapide"
description: "Démarrez StrokeMouse : accordez l’Accessibilité, activez les gestes et dessinez votre première trajectoire."
titleTemplate: "StrokeMouse"
---

# Démarrage rapide

Lancez StrokeMouse et vérifiez votre premier geste en quelques étapes.

## Prérequis

- **macOS 14 Sonoma** ou ultérieur
- N’importe quelle souris (le déclencheur par défaut est le bouton **droit** ; vous pouvez le changer par geste)
- Accepter d’accorder l’**Accessibilité**

## Cinq étapes

### 1. Lancez l’app

Une icône StrokeMouse apparaît dans la barre des menus. L’app vit d’abord dans la barre des menus ; vous pouvez masquer l’icône du Dock dans les réglages.

### 2. Accordez l’Accessibilité

Ouvrez **Réglages → Autorisations**, allez dans **Réglages Système → Confidentialité et sécurité → Accessibilité** et activez StrokeMouse.

::: tip
Sans confiance, le moteur ne fait **pas** semblant d’écouter. L’état est visible dans la barre des menus et la page Autorisations — pas d’échec silencieux.
:::

### 3. Vérifiez que les gestes sont activés

Dans la barre des menus, confirmez que les gestes sont actifs / reprenez-les s’ils sont en pause.

### 4. Ouvrez la liste des gestes

**Réglages → Gestes** affiche les valeurs par défaut (par ex. trait vers le haut → Mission Control). Créez les vôtres à tout moment.

### 5. Dessinez le premier trait

1. Maintenez le **déclencheur** du geste (bouton **droit** par défaut)
2. Faites glisser un chemin (par ex. vers le haut)
3. Relâchez

En cas de correspondance, l’action liée s’exécute. Tant que le déclencheur est maintenu, un **HUD de trajectoire en direct** se dessine à l’écran.

## Clic ou geste

| Comportement | Résultat |
|----------|--------|
| Appuyer sur le déclencheur, **presque pas bouger**, relâcher | Clic court : un clic synthétique est rejoué — **le menu contextuel fonctionne encore** |
| Dépasser la distance minimale, relâcher | Mode geste : la séquence down/drag/up est réservée au geste — **pas** de menu contextuel |

Le bouton gauche et les boutons non surveillés passent toujours.

## Suite

- [Installation et compilation](./installation) — compiler vers `output/StrokeMouse.app`
- [Autorisations](./permissions) — Accessibilité et Automatisation
- [Gestes](./gestures) — déclencheurs, correspondance, portée
- [Réglages et barre des menus](./settings#scroll-enhancement) — inversion et lissage du défilement
- [Actions](./actions) — raccourcis, fenêtres, scripts
