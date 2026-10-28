---
title: "Installation et compilation"
description: "Installer StrokeMouse ou compiler depuis les sources. macOS 14+, CLI, Xcode, signature et tests."
keywords: "installer StrokeMouse,compiler depuis les sources,xcodebuild,signature,macOS 14"
---

# Installation et compilation

Homebrew est la méthode d’installation recommandée. Vous pouvez aussi récupérer les builds de production **Apple Silicon / Intel** sur la [page de téléchargement](/fr/download). Pour compiler vous-même, suivez les étapes ci-dessous.

## Prérequis

| Élément | Exigence |
|------|-------------|
| OS | macOS 14 Sonoma ou ultérieur |
| Build de développement | Xcode 16+ |
| Génération du projet | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |

## Homebrew (recommandé)

Installez depuis le [Licoy Homebrew Tap maintenu par le projet](https://github.com/Licoy/homebrew-tap) :

```bash
brew install --cask licoy/tap/strokemouse
```

StrokeMouse gère aussi les mises à jour dans l’app. Pour forcer Homebrew à vérifier et installer une mise à niveau :

```bash
brew upgrade --cask --greedy strokemouse
```

La désinstallation conserve les réglages par défaut. Ajoutez `--zap` pour les supprimer aussi :

```bash
brew uninstall --cask strokemouse
brew uninstall --cask --zap strokemouse
```

Homebrew et le téléchargement manuel utilisent les mêmes paquets de version, donc les notes Gatekeeper et Accessibilité du premier lancement s’appliquent aux deux.

## Cloner

```bash
git clone https://github.com/Licoy/StrokeMouse.git
cd StrokeMouse
```

## Recommandé : compilation en CLI

Le chemin de sortie stable `output/StrokeMouse.app` réduit les redemandes d’Accessibilité.  
Le Debug s’affiche comme **StrokeMouse Dev** (Bundle ID `com.strokemouse.app.dev`) et peut être autorisé à côté de l’app **StrokeMouse** de production :

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app (Accessibilité : StrokeMouse Dev)
./scripts/build.sh --open    # ouvrir une fois terminé
./scripts/build.sh --release # Release (même nom / Bundle ID que les builds livrés)
```

Après avoir modifié `project.yml` ou ajouté/supprimé des sources :

```bash
./scripts/generate_project.sh
```

## Lancer dans Xcode

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

Scheme **StrokeMouse** → Run.

## Signature du code

| Élément | Valeur |
|------|--------|
| Bundle ID | Release : `com.strokemouse.app` ; Debug : `com.strokemouse.app.dev` (nom StrokeMouse Dev) |
| Identité de développement | **`StrokeMouse Dev`** dans le trousseau (auto-signée ; builds locaux) |
| Identité Release | **`StrokeMouse Release`** auto-signée + Hardened Runtime (identité stable ; **les utilisateurs n’installent pas le certificat**) |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` ou package (smoke uniquement ; **l’Accessibilité ne survit pas aux mises à jour**) |
| Notarisation | Pas de notarisation Apple / Developer ID pour l’instant |

::: warning
Si Gatekeeper bloque une GitHub Release au premier lancement, cliquez l’app en maintenant Contrôle puis choisissez Ouvrir, ou Réglages Système → Confidentialité et sécurité → Ouvrir quand même.

**Accessibilité** : les paquets officiels utilisent une identité auto-signée stable, donc **les mises à jour dans l’app signées avec le même certificat conservent généralement l’autorisation**. Migrer depuis d’anciens builds ad-hoc ou changer de certificat exige **une** nouvelle autorisation. Les utilisateurs finaux n’installent **pas** le certificat de l’éditeur.
:::

## Artefacts de version

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

Chaque architecture produit ZIP, TAR.GZ et DMG. Le ZIP alimente aussi les mises à jour Sparkle. Voir `RELEASING.md` à la racine du dépôt pour les versions et les tags.

## Tests

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## Dépendances

- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) — ouverture à l’ouverture de session
- [Sparkle](https://github.com/sparkle-project/Sparkle) — signature des mises à jour et installation dans l’app
- Système : `CGEventTap`, Accessibilité, Apple Events facultatifs

## Suite

Après une compilation réussie, continuez avec [Autorisations](./permissions) et [Démarrage rapide](./getting-started).
