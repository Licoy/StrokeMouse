---
title: "Actions"
description: "Actions StrokeMouse : raccourcis, commandes système, ouvrir une app, URL, touches média, fenêtres, Shell et AppleScript."
keywords: "actions de geste,raccourcis,Shell,AppleScript,fenêtres,touches média"
---

# Actions

En cas de correspondance, `ActionExecutor` dispatche l’action configurée.

## Vue d’ensemble

| Type | Rôle | Notes |
|------|----------------|-------|
| Aucune | Correspondance seule / test | — |
| **Raccourci** | Injecter un accord de touches | Nécessite l’Accessibilité |
| **Système** | Mission Control, Fenêtres de l’application, Espace précédent / suivant | Nécessite l’Accessibilité ; doit correspondre aux raccourcis système |
| **Ouvrir une app** | Choisir une app installée par icône et la lancer | Stocké comme bundle id |
| **Ouvrir une URL** | Navigateur / gestionnaire par défaut | — |
| **Média** | Lecture/pause, pistes, volume, sourdine | — |
| **Fenêtre** | Fermer, réduire, zoomer, agrandir au maximum, plein écran, masquer, centrer | Nécessite AX |
| **Shell** | Exécuter une commande shell (éditeur coloré) | **Privilège élevé** |
| **AppleScript** | Préréglages intégrés ou script perso (coloré) | **Privilège élevé** ; Automatisation parfois requise |

## Raccourci

Les raccourcis se règlent uniquement par enregistrement ; le champ d’affichage est en lecture seule. Cliquez **Enregistrer**, pressez les touches dans l’ordre voulu, puis relâchez-les toutes. Esc seul annule.

Les raccourcis avec une touche normale (par ex. `⌘⌥Q`) et ceux composés uniquement de modificateurs (par ex. `⌘⌥`) sont pris en charge. Le résultat s’affiche dans l’ordre d’appui. Les modificateurs pris en charge sont Command, Option, Control, Shift et Fn/Globe. Fn peut s’utiliser seul ou avec d’autres touches, par ex. `fn⌃⇧←`, qui dispose les fenêtres à gauche et à droite sous macOS 15 ou ultérieur.

Relâchez toutes les touches de modification avant de lancer l’enregistrement, puis appuyez sur les touches dans l’ordre où elles doivent être rejouées. Fn doit être pressée physiquement ; une touche réassignée à Fn dans Réglages Système, comme Verr. Maj (Caps Lock), fonctionne aussi. Verr. Maj peut rester activé après avoir relâché sa touche.

## Système

Choisissez le type d’action « Système » pour exécuter l’une de ces commandes :

| Commande | Raccourci par défaut | Cible |
|------|------|------|
| Mission Control | ⌃↑ | Bureau actuel, sans activer la fenêtre figée |
| Fenêtres de l’application | ⌃↓ | Active d’abord l’app et la fenêtre figées |
| Espace précédent | ⌃← | Bureau actuel, sans activer la fenêtre figée |
| Espace suivant | ⌃→ | Bureau actuel, sans activer la fenêtre figée |

Ces commandes envoient le raccourci correspondant défini dans Réglages Système › Clavier › Raccourcis clavier › Mission Control ; les valeurs par défaut sont celles de macOS. Si vous les avez modifiés dans le système, enregistrez un autre raccourci dans l’éditeur ou revenez à l’original avec « Rétablir le raccourci par défaut ». L’éditeur lit ces réglages système et avertit si le raccourci correspondant est désactivé ou diffère de celui configuré ici ; « Utiliser le raccourci système » reprend alors la valeur du système. StrokeMouse ne modifie pas les réglages système.

Si une commande utilise son raccourci par défaut alors qu’il est désactivé dans Réglages Système, son exécution affiche une erreur au lieu de ne rien faire.

Ce sont des commandes ponctuelles, exécutées une fois par déclenchement, sans l’animation interactive qui suit les doigts des gestes natifs à quatre doigts. Les préréglages de gestes tactiles « Quatre doigts vers le haut / bas » utilisent les commandes système Mission Control et Fenêtres de l’application.

Les configurations et exports contenant des commandes système ou Déplacer pour défiler utilisent le format **v4** ; avec seulement des raccourcis Fn, c’est **v3**, sinon **v2**. Les anciennes versions ne peuvent pas lire les fichiers v3/v4.

## Ouvrir une app

Dans le sélecteur d’action, choisissez parmi les **apps installées** par icône (recherche ou parcours d’un `.app`) — pas besoin de taper un bundle id à la main (le lancement utilise quand même l’identifiant de paquet). Le nom affiché sert à la liste.

## Ouvrir une URL

Toute URL que le système peut ouvrir. Le geste par défaut « Ouvrir GitHub » utilise ce type.

## Média

| Commande | Rôle |
|---------|------|
| playPause | Lecture / pause |
| nextTrack / previousTrack | Sauter |
| volumeUp / volumeDown / mute | Volume |

## Fenêtre

| Commande | Rôle |
|---------|------|
| close | Fermer la fenêtre |
| minimize | Réduire |
| zoom | Taille choisie par l’app |
| maximize | Agrandir la fenêtre au maximum |
| fullscreen | Plein écran |
| hide | Masquer l’app |
| center | Centrer la fenêtre |

Les actions de fenêtre ciblent la fenêtre exacte capturée au début du geste, plutôt que celle au premier plan lors de l’exécution. Masquer l’app utilise l’app capturée. Une fenêtre absente, une action non prise en charge ou une autorisation d’Accessibilité manquante entraîne un message d’échec.

**Agrandir la fenêtre au maximum** remplit la zone disponible de l’écran où se trouve la fenêtre, en tenant compte de la barre des menus et du Dock. Répéter l’action conserve cette taille sans rétablir la précédente. `zoom` utilise la taille choisie par l’app et `fullscreen` passe en plein écran, tandis que l’agrandissement reste sur le bureau. Cette version ne quitte pas le plein écran avant d’agrandir : quittez-le d’abord manuellement. Si la position ou la taille ne peut pas être modifiée, ou si la fenêtre n’atteint pas les dimensions et la position requises, par exemple à cause de restrictions de l’app, un échec est affiché.

Les configurations et exports avec cet agrandissement comme action principale ou secondaire utilisent le format **v5** et nécessitent une version compatible. Les autres conservent les règles v2/v3/v4 existantes.

## Shell

Exécute une chaîne de commande locale. L’éditeur colore la syntaxe pour relire plus facilement les longues commandes.

::: danger Risque
Le Shell a votre pouvoir utilisateur sur les fichiers et processus. Ne collez que des commandes que vous comprenez et en lesquelles vous avez confiance.
:::

## AppleScript

Utilisez un **préréglage intégré** (sommeil, vider la Corbeille, verrouiller l’écran, économiseur, se déconnecter / redémarrer / éteindre, basculer le mode sombre, masquer les autres, sourdine / rétablir, panneau Forcer à quitter, capture vers le presse-papiers, ouvrir Téléchargements) ou passez à un script **personnalisé**. Contrôler d’autres apps peut exiger l’**Automatisation**. L’éditeur colore aussi la syntaxe.

::: danger Risque
Même classe de risque que le Shell. N’exécutez jamais de scripts non fiables.
:::

## Bien choisir

| Objectif | Préférer |
|------|--------|
| Raccourcis système / d’app | Raccourci |
| Mission Control / espaces | Système |
| Lancer un logiciel | Ouvrir une app |
| Saut façon signet | Ouvrir une URL |
| Musique et volume | Média |
| Gestion des fenêtres | Fenêtre |
| Automatisation lourde | Shell / AppleScript (avec prudence) |

Persistance : [Fichier de config](./config-file).
