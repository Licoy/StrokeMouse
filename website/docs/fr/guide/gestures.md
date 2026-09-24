---
title: "Gestes"
description: "Système de gestes StrokeMouse : déclencheurs, rejeu du clic court, correspondance libre, portée d’app et exemples par défaut."
titleTemplate: "StrokeMouse"
---

# Gestes

Déclencheurs, échantillonnage et règles de correspondance pour des traits personnalisés fiables. L’inversion et le lissage du défilement ne sont pas dans la bibliothèque de gestes ; voir [Réglages et barre des menus](./settings#scroll-enhancement).

## Pipeline

```text
Maintenir le déclencheur → échantillonner le chemin → distance ≥ trait min
     → relâcher → correspondre parmi les candidats du même déclencheur → exécuter l’action
```

1. **Le déclencheur vit sur chaque profil de geste** (bouton droit par défaut)
2. Le moteur ne surveille que les boutons des gestes **activés**
3. Au relâchement, la **portée d’app** + le `bundleIdentifier` au premier plan filtrent les candidats

## Déclencheurs

Par geste :

| Déclencheur | Notes |
|---------|--------|
| Droit | Par défaut ; un clic court ouvre encore le menu contextuel |
| Milieu | Clic molette |
| Latéral arrière / avant | Boutons pouce typiques |

Le bouton gauche et les boutons non surveillés **passent toujours**.

## Rejeu du clic court

Après que le moteur a capturé l’appui du déclencheur :

- Distance **sous** `minStrokeDistance` : un down/up synthétique marqué **rejoue** un clic normal (les menus marchent)
- Dès qu’un vrai trait commence : le groupe down/drag/up est **réservé au geste**, pas livré à l’app de premier plan

## Correspondance de trajectoire libre

Reconnaisseur principal :

- Rééchantillonnage ordonné selon la longueur d’arc
- Normalisation 1D / 2D
- Recherche de rotation limitée à **±12°**
- Score ≥ seuil
- **Nombre de segments / structure des virages** comme portes dures (non compensables par le score)
- **Pas** de miroir, d’inversion ni de repli near-miss

Enregistrez des traits propres à vitesse modérée ; réenregistrez les formes ornées jusqu’à stabilité.

## HUD en direct

Tant que le déclencheur est maintenu, le chemin actuel est dessiné à l’écran pour s’aligner sur le modèle.

## Portée d’app

| Portée | Comportement |
|-------|----------|
| Globale | Correspond dans n’importe quelle app au premier plan |
| Apps précises | Seulement si l’app au premier plan est dans la liste |

Dans l’éditeur, choisissez les **apps installées par icône** (recherche, multi-sélection ou parcours d’un `.app`) — pas besoin de taper les bundle ids à la main (la correspondance utilise quand même les identifiants de paquet). Utile pour des gestes uniquement navigateur ou uniquement IDE.

La colonne de portée de la liste affiche « Global » ou un jeu compact d’icônes. Sous **Réglages → Gestes**, la barre latérale gauche parcourt Global et les groupes par app ; créer un geste sous un nœud préremplit cette portée.

## Activer / désactiver

Interrupteur par geste. Les profils désactivés quittent l’ensemble surveillé et le pool de correspondance.

## Exemples par défaut

Gestes intégrés (le déclencheur est modifiable par profil) :

<DefaultGestures />

## Édition

**Réglages → Gestes** pour ajouter, modifier, supprimer, enregistrer des chemins, choisir des actions. Voir [Réglages et barre des menus](./settings) et [Actions](./actions).
