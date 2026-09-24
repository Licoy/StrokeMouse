---
title: "Fichier de config"
description: "Config StrokeMouse : import/export UI de paquets JSON de gestes, plus sauvegarde complète de gestures.json."
titleTemplate: "StrokeMouse"
---

# Fichier de config

Les gestes et préférences associées persistent en **JSON**. Préférez l’UI pour **importer / exporter** des gestes sélectionnés ; copiez le fichier local pour une sauvegarde de toute la bibliothèque.

## Import / export dans l’UI

**Réglages → Gestes** :

1. **Exporter** — multi-sélectionner des gestes → enregistrer un paquet JSON (même champ de version que le format de config)
2. **Importer** — choisir un fichier JSON ; si le contenu existe déjà, **ignorer les doublons** ou **importer de force** (les doublons forcés sont désactivés par défaut)

Pratique pour partager quelques gestes favoris ou synchroniser un sous-ensemble entre machines sans remplacer toute la bibliothèque.

## Chemin de la bibliothèque complète

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

Les réglages peuvent **Afficher dans le Finder**.

## Conseils

| Scénario | Approche |
|----------|----------|
| Partager / synchroniser certains gestes | **Réglages → Gestes → Exporter / Importer** |
| Sauvegarde complète | Copier le dossier `StrokeMouse` ou seulement `gestures.json` |
| Défilement amélioré | Reste sur ce Mac. Absent de `gestures.json` et de la synchro de sauvegarde ; sur un autre Mac, réglez-le de nouveau dans **Réglages → Défilement** |
| Nouvelle machine | Installer + autoriser, puis importer un paquet **ou** remplacer `gestures.json` et relancer |
| Édition à la main | Garder un JSON valide ; préférer des champs optionnels rétrocompatibles |
| Fichier corrompu | Supprimer le fichier pour régénérer les défauts (données perso perdues) |

::: warning
L’app peut réécrire le fichier pendant qu’elle tourne. Quittez l’app (ou évitez les écritures concurrentes) avant d’écraser le fichier de bibliothèque complète.
:::

## Contenu

Chaque profil a en général :

- id, nom, activé
- **déclencheur** (droit / milieu / latéral…)
- **motif** (points de trajectoire libre ; les anciennes listes de directions se décodent encore)
- **action** (raccourci, app, URL, média, fenêtre, shell, AppleScript…)
- **portée** (globale ou bundle ids)
- notes

Les champs exacts suivent les modèles `Codable` de l’app ; les mises à niveau doivent rester lisibles autant que possible. L’import migre les anciennes listes de directions vers free-path.

## UI et JSON

Préférez **Réglages → Gestes** pour l’édition quotidienne et l’import/export de paquets. Le JSON de bibliothèque complète sert à :

- sauvegardes complètes et migrations de machine
- stocker des configs personnelles dans git (retirez les scripts privés)
- réparer des fichiers cassés

## Confidentialité

Shell / AppleScript peuvent contenir des chemins ou des jetons. Masquez-les avant de partager des paquets d’export ou des fichiers de config.
