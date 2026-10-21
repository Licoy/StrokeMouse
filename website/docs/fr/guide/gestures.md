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

## Associations de boutons souris

Dans **Ajouter → Boutons souris**, associez une action à un bouton latéral (précédent / suivant) ou au bouton du milieu : un simple clic l’exécute, sans dessiner. Le menu propose deux préréglages : « Bouton latéral précédent · Précédent » (⌘[) et « Bouton latéral suivant · Suivant » (⌘]).

- L’action s’exécute au relâchement. Si le même bouton sert aussi à dessiner, un appui qui reste sous `minStrokeDistance` exécute l’association et un appui plus long est reconnu comme un dessin : un seul appui ne déclenche jamais les deux
- Si l’app cible n’a que l’association pour ce bouton, sans geste dessiné, bouger en le maintenant compte quand même comme un clic
- Activez **Exiger une touche de modification** et choisissez Fn / Control / Option / Shift / Command pour ne déclencher l’association que lorsque exactement cette touche est maintenue (par ex. ⌘ + bouton latéral précédent) ; une association sans modificateur ne se déclenche jamais tant qu’un modificateur est maintenu, donc un même bouton peut porter les deux. Si le modificateur choisi lance aussi le dessin trackpad, celui-ci prend la main et l’association ne s’exécute pas
- Les portées toutes les apps / groupe d’apps / apps sélectionnées s’appliquent comme d’habitude et seul le niveau le plus précis compte ; plusieurs associations à ce niveau forment un conflit : rien ne s’exécute et une notification s’affiche
- Si l’app cible n’a ni geste ni association pour ce bouton, le clic passe tel quel, par exemple pour garder le précédent / suivant natif du navigateur
- Le bouton droit ne peut pas être associé, pour ne pas bloquer le menu contextuel ; une association réussie n’affiche pas de notification de correspondance

## Rejeu du clic court

Après que le moteur a capturé l’appui du déclencheur :

- Distance **sous** `minStrokeDistance` : un down/up synthétique marqué **rejoue** un clic normal (les menus marchent) ; si l’app cible associe ce bouton, l’association s’exécute à la place
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
