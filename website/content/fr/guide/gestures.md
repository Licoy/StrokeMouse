---
title: "Gestes"
description: "Système de gestes StrokeMouse : déclencheurs, rejeu du clic court, correspondance libre, portée d’app et exemples par défaut."
keywords: "gestes souris,déclencheur,freePath,correspondance,portée d’application"
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

## Combinaisons souris

Créez-en une dans **Ajouter → Combinaisons souris** : aucun tracé à enregistrer, et toutes les actions, fenêtres cibles et portées s’appliquent.

| Déclencheur | Action de la souris | Quand elle s’exécute |
|--------|------|------|
| Maintenir le bouton droit | Défiler vers le haut / bas | À chaque cran de molette, donc répétable |
| Maintenir le bouton droit | Clic gauche | Le premier clic gauche de chaque maintien du bouton droit |
| Maintenir le bouton droit | Déplacer pour défiler | Défilement horizontal / vertical dès que le pointeur a bougé d’au moins 10 points ; s’arrête au relâchement |
| Bord de l’écran (haut / bas / gauche / droite) | Clic droit | Bouton droit appuyé puis relâché au bord choisi, sans commencer de tracé |
| Bord de l’écran (haut / bas / gauche / droite) | Défiler vers le haut / bas | Sans bouton droit, au plus une fois toutes les 100 ms |

- Un maintien ou un clic droit qui lance une combinaison n’ouvre pas le menu contextuel et n’est pas reconnu comme un tracé ; un clic droit qui ne déclenche rien ouvre le menu comme d’habitude
- « Maintenir le bouton droit + clic gauche » passe avant l’action secondaire ; sans cette combinaison, l’action secondaire fonctionne comme avant
- Les sens de molette non configurés et les apps sans combinaison défilent normalement ; les crans utilisés par une combinaison ne font pas défiler la page
- Bouton droit maintenu, une molette haute précision exécute l’action au plus toutes les 120 ms, pour qu’un seul défilement ne change pas plusieurs onglets d’affilée ; le trackpad, le défilement inertiel et les images de lissage d’autres outils de défilement ne déclenchent jamais d’action
- Un bord correspond aux 3 points à l’intérieur des limites de chaque écran, jonction entre écrans adjacents comprise ; un coin qui correspond à deux réglages du même niveau est un conflit
- Portées et conflits fonctionnent comme pour les associations de boutons : seul le niveau le plus précis compte, et plusieurs entrées à ce niveau forment un conflit, donc rien ne s’exécute et une notification s’affiche ; une politique d’app peut désactiver à part les « Combinaisons souris » globales

**Déplacer pour défiler** : choisissez « Déplacer pour défiler » dans le mode « Maintenir le bouton droit », puis réglez si besoin « Sensibilité » (0,25 à 4×, par pas de 0,05) et « Inverser la direction » ; par défaut, le contenu suit le pointeur. Le défilement ne commence qu’une fois que le pointeur a dépassé un seuil fixe de 10 points depuis l’appui du bouton droit, indépendamment de la « Distance minimale de tracé » ; relâcher avant rejoue un clic droit normal, donc le menu contextuel reste utilisable, et une fois le défilement commencé, le relâchement ne rejoue aucun clic et ne reconnaît aucun tracé. C’est le contenu sous le pointeur au début du défilement qui défile, sans activer de fenêtre ; la portée d’app utilise toujours la cible figée à l’appui du bouton droit. Le relâchement arrête tout immédiatement, sans inertie, verrouillage ni recentrage du pointeur, donc les bords de l’écran limitent la course. Ce mode n’a ni action ordinaire ni action secondaire : enregistrez-le, puis testez-le hors de l’éditeur en maintenant le bouton droit et en déplaçant la souris.

Au niveau de portée le plus précis (app > groupe d’apps > global), un geste Déplacer pour défiler ne peut coexister ni avec un dessin au bouton droit ni avec un autre geste Déplacer pour défiler ; à l’exécution, un tel conflit n’exécute rien et affiche une notification dédiée. Les conflits certains (global contre global, listes d’apps qui se recoupent ou même groupe d’apps) sont bloqués partout : l’enregistrement dans l’éditeur, l’activation par case à cocher ou en lot, « Déplacer vers » et la suppression d’un groupe d’apps en gardant ses gestes en global sont refusés avec un message qui nomme les gestes en conflit ; « Dupliquer » crée la copie désactivée si elle devait entrer en conflit ; l’import fait entrer les gestes en conflit désactivés et les liste ; les gestes activés déjà en conflit (par exemple après la restauration d’une sauvegarde) affichent une icône d’avertissement dans la liste des gestes. Les gestes existants ne sont jamais supprimés ni désactivés automatiquement ; les chevauchements dynamiques entre groupes d’apps différents restent résolus à l’exécution.

## Rejeu du clic court

Après que le moteur a capturé l’appui du déclencheur :

- Distance **sous** `minStrokeDistance` : un down/up synthétique marqué **rejoue** un clic normal (les menus marchent) ; si l’app cible associe ce bouton, l’association s’exécute à la place ; si « Déplacer pour défiler » s’applique au bouton droit, le seuil est fixé à 10 points
- Dès qu’un vrai trait ou un défilement par déplacement commence : le groupe down/drag/up est **réservé au geste**, pas livré à l’app de premier plan

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
