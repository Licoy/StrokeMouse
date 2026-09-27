[English](./README.md) · [简体中文](./README_zh-Hans.md) · [繁體中文](./README_zh-Hant.md) · [한국어](./README_ko.md) · [日本語](./README_ja.md) · [Русский](./README_ru.md) · **Français**

<div align="center">
  <img src="design/logo/stroke-mouse-app-icon.png" width="128" alt="StrokeMouse" />
  <h1>StrokeMouse</h1>
  <p>
    <a href="./LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/License-AGPL%20v3-blue.svg" /></a>
  </p>
</div>

Outil de personnalisation des gestes souris et trackpad pour macOS. Dessinez une trajectoire en maintenant un bouton de souris, dessinez au trackpad avec une seule touche de modification, ou utilisez des gestes tactiles expérimentaux à plusieurs doigts. En cas de correspondance, l’app exécute des raccourcis, ouvre des applications, pilote les fenêtres, les touches média, Shell / AppleScript, etc. Les gestes peuvent s’appliquer **globalement ou à une App précise**, les configurations sont **importables / exportables**, tout s’exécute en local et reste dans la barre des menus.

<p align="center">
  <a href="https://strokemouse.com/video/strokemouse-promo.mp4?v=d269ecf1"><img src="website/docs/public/video/strokemouse-promo-thumb.jpg" width="800" alt="Vidéo de présentation de StrokeMouse" /></a>
  <br />
  <sub><a href="https://strokemouse.com/video/strokemouse-promo.mp4?v=d269ecf1">▶ Voir la vidéo de présentation (1:42, texte à l’écran en chinois simplifié)</a></sub>
</p>

## Aperçu

| Liste des gestes | Test de geste |
|:---:|:---:|
| <img src="website/docs/public/screenshots/1.png" width="400" alt="Liste des gestes" /> | <img src="website/docs/public/screenshots/2.png" width="400" alt="Test de geste" /> |

| Réglages généraux | Autorisations et état du moteur |
|:---:|:---:|
| <img src="website/docs/public/screenshots/3.png" width="400" alt="Réglages généraux" /> | <img src="website/docs/public/screenshots/4.png" width="400" alt="Autorisations et état du moteur" /> |

| Nouveau geste · enregistrement | Portée d’application |
|:---:|:---:|
| <img src="website/docs/public/screenshots/5.png" width="400" alt="Nouveau geste · enregistrement" /> | <img src="website/docs/public/screenshots/6.png" width="400" alt="Portée d’application" /> |

## Fonctionnalités

- **Toujours dans la barre des menus** : activer / désactiver les gestes, ouvrir les réglages, quitter ; l’icône change de teinte selon l’état (normal / en pause / autorisation manquante) ; possibilité de **masquer l’icône de la barre des menus** (confirmation si le Dock est aussi masqué ; ensuite, cliquez le Dock ou relancez l’app pour ouvrir les réglages)
- **Bibliothèque de gestes** : barre latérale organisée en **global / par App** (la portée est préremplie à la création) ; recherche / filtre / tri ; activation, désactivation et suppression groupées ; **import / export JSON** (doublons ignorés ou importés de force)
- **Dessin souris** : chaque geste peut utiliser indépendamment le bouton droit, le bouton du milieu ou un bouton latéral ; seuls les boutons des profils activés sont surveillés
- **Dessin trackpad** : maintenez exactement une touche parmi Fn / Control / Option / Shift / Command (Fn par défaut) et déplacez le pointeur ; une autre touche prise en charge annule cette reconnaissance
- **Gestes tactiles expérimentaux** : le trackpad intégré prend en charge 34 classes — tapotements et double tapotements à trois à cinq doigts, balayages dans quatre directions, ainsi que pincements / écartements et rotations horaire / antihoraire à deux à cinq doigts
- **Interrupteur général des gestes tactiles** : désactivez le canal tactile sans supprimer les gestes configurés ; une panne du backend privé ne dégrade que le canal tactile, le dessin souris et trackpad reste disponible
- **Défilement amélioré** : inversez séparément la molette et le trackpad / Magic Mouse sur chaque axe, et lissez éventuellement la molette crantée (doux / standard / réactif, ou vitesse, durée et accélération personnalisées). Les exclusions suivent l’app au premier plan. Ces réglages restent sur ce Mac et ne font pas partie de la synchro de sauvegarde. Un autre outil de défilement peut traiter les événements deux fois ; les apps qui ne lisent que des pas entiers (certains jeux, VM, bureaux distants) doivent être exclues
- **Cible propre à chaque geste** : choisissez l’app au premier plan ou l’app sous le pointeur au moment de l’appui sur le déclencheur ; s’il existe une fenêtre normale, elle est aussi figée, et les contrôles de portée ainsi que les actions liées à la cible réutilisent toujours cette cible
- **Reconnaissance de trajectoire libre** : rééchantillonnage selon la longueur d’arc + normalisation 1D/2D + rotation limitée ; portes structurelles sur les virages marqués ; seuil de correspondance global réglable dans Général ; HUD de trajectoire en direct tant que le déclencheur est maintenu
- **Portée App** : globale, ou ajout par icône parmi les applications installées (recherche / parcours de `.app`)
- **Actions variées** : raccourcis, ouvrir / basculer une App, URL, touches média, actions de fenêtre, Shell / AppleScript (éditeur avec coloration syntaxique ; AppleScript inclut sommeil, verrouillage de l’écran, vider la Corbeille, plus du personnalisé)
- **Confort** : interface en anglais, chinois simplifié, chinois traditionnel, coréen, japonais, russe et français (ou langue du système), apparence claire / sombre (système ou forcée), ouverture à l’ouverture de session, masquage du Dock / de l’icône de menu, mises à jour Sparkle dans l’app (repli vers GitHub Releases en cas d’échec)

## Configuration requise

- macOS 14 Sonoma ou ultérieur
- Xcode 16+ (pour les builds de développement)
- Une souris ou un trackpad suffit pour les gestes dessinés ; le multitouch direct vise surtout le trackpad intégré des Mac
- Le Magic Trackpad externe est pris en charge au mieux, selon le modèle et la version de macOS

## Installation

### Homebrew (recommandé)

Installez depuis le [Licoy Homebrew Tap](https://github.com/Licoy/homebrew-tap) maintenu par le projet StrokeMouse :

```bash
brew install --cask licoy/tap/strokemouse
```

StrokeMouse prend aussi en charge les mises à jour dans l’app. Pour forcer Homebrew à vérifier et installer une mise à niveau :

```bash
brew upgrade --cask --greedy strokemouse
```

La désinstallation conserve les réglages par défaut. Ajoutez `--zap` pour les supprimer aussi :

```bash
brew uninstall --cask strokemouse
brew uninstall --cask --zap strokemouse
```

Vous pouvez aussi télécharger le DMG de votre architecture sur la [page de téléchargement officielle](https://strokemouse.com/fr/download). Les versions actuelles utilisent une signature auto-signée stable et ne sont pas notariées par Apple. Si Gatekeeper bloque le premier lancement, cliquez l’app en maintenant Contrôle puis choisissez Ouvrir, ou utilisez Réglages Système → Confidentialité et sécurité → Ouvrir quand même.

## Autorisations

| Autorisation | Usage |
|--------------|--------|
| **Accessibilité** | Écoute globale souris / modificateur / défilement (`CGEventTap`), injection de raccourcis, actions AX sur les fenêtres |
| **Automatisation** | Facultatif ; requis lorsque AppleScript pilote d’autres apps |

Au premier lancement ou dans **Réglages → Autorisations**, utilisez le **guide d’autorisation** intégré : ouvrez les Réglages Système et faites glisser StrokeMouse dans la liste. Sans confiance, le moteur ne fait pas semblant d’écouter.

### Gestes tactiles expérimentaux

Les gestes tactiles chargent le `MultitouchSupport` non documenté d’Apple à l’exécution via `dlopen` / `dlsym` ; ce framework privé n’est pas lié statiquement. Il peut cesser de fonctionner après une mise à jour de macOS. Un framework, un symbole ou un appareil manquant, ou un échec de démarrage de l’appareil, s’affiche comme une panne du canal tactile ; le dessin souris et trackpad continue, sans repli simulé ni nouvelle tentative silencieuse.

StrokeMouse n’intercepte pas les événements natifs du trackpad, un geste système peut donc se produire en même temps que l’action liée. Les trajectoires tactiles brutes ne sont ni stockées ni journalisées. La première sauvegarde, activation ou importation de profils de gestes tactiles activés affiche une confirmation de risque expérimental. L’interrupteur général peut ensuite mettre les gestes tactiles en pause sans supprimer les profils.

Les 34 classes de gestes tactiles prises en charge :

| Famille | Doigts | Variantes | Nombre |
|---------|--------|-----------|--------|
| Tapotement | trois / quatre / cinq | simple, double | 6 |
| Balayage | trois / quatre / cinq | haut, bas, gauche, droite | 12 |
| Échelle | deux / trois / quatre / cinq | pincer, écarter | 8 |
| Rotation | deux / trois / quatre / cinq | antihoraire, horaire | 8 |
| **Total** |  |  | **34** |

La première version ne prend pas en charge les tapotements / balayages à deux doigts, les combinaisons de modificateur, l’identité d’un doigt précis, les actions répétées en continu ni les seuils de reconnaissance réglables par l’utilisateur.

## Compilation et exécution

### Dépendances

```bash
brew install xcodegen
```

### Générer le projet et l’ouvrir

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

Ou **Run** directement dans Xcode (Scheme : `StrokeMouse`).

### Compilation en ligne de commande (recommandé)

Produit un chemin stable `output/StrokeMouse.app` dans le dépôt, ce qui limite les redemandes d’Accessibilité.  
Le Debug s’affiche comme **StrokeMouse Dev** (Bundle ID `com.strokemouse.app.dev`) et peut être autorisé séparément de la version **StrokeMouse** :

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app (Accessibilité : StrokeMouse Dev)
./scripts/build.sh --open    # ouvrir après la compilation
./scripts/build.sh --release # Release (nom affiché / Bundle ID identiques au paquet final)
```

### Empaquetage de version

Génère ZIP, TAR.GZ et DMG par architecture, et vérifie la signature, les entitlements et l’intégrité des artefacts (identité auto-signée stable **`StrokeMouse Release`** par défaut, pour que l’Accessibilité survive aux mises à jour Sparkle) :

```bash
# Première fois en local : ./scripts/generate-codesign-cert.sh --import
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

Voir `RELEASING.md` / `certs/README.md` pour la publication et les secrets CI.

Publication de version : `./bump.sh -v x.y.z [-p]`. Retaguer la même version et pousser : `./bump.sh -v x.y.z --force`.

### Tests

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## Utilisation

1. Lancez l’app ; une icône de souris apparaît dans la barre des menus  
2. Accordez l’**Accessibilité**, puis activez les gestes depuis la barre des menus  
3. Ouvrez **Réglages → Gestes** pour consulter les gestes par défaut ou en créer  
4. Choisissez une entrée : dessin en maintenant un déclencheur souris, dessin trackpad avec une touche de modification, ou geste tactile configuré
5. En cas de correspondance, l’action liée s’exécute  

> **Clic court et geste** : l’appui et le relâchement du déclencheur sont temporairement capturés par le moteur. Si vous relâchez avant la « distance minimale de trait », un clic normal est rejoué et le menu contextuel reste utilisable. Une fois le dessin commencé, le glissement déplace le curseur système et le HUD, mais l’app au premier plan ne reçoit pas de paire down/up — aucun menu contextuel n’apparaît ni n’est sélectionné. Le clic gauche et les boutons non configurés comme déclencheurs passent toujours.

> **Dessin trackpad** : la surveillance des modificateur est en listen-only et ne consomme pas les événements clavier ; un chemin court n’exécute aucune action. Le chemin suit le pointeur système, donc trackpad ou souris peuvent le déplacer. StrokeMouse ne supprime pas l’effet normal du modificateur dans l’app active.

> Les raccourcis activent d’abord l’app figée et amènent aussi sa fenêtre exacte au premier plan si elle a été capturée, ce qui peut changer le focus ou l’espace. Les emplacements sans fenêtre normale, comme le bureau du Finder, peuvent encore exécuter des raccourcis et **Masquer l’app** ; Fermer, Réduire, Zoom, Plein écran et Centrer exigent une fenêtre exacte. Un clic court n’active jamais la cible.

Exemples de gestes par défaut (bouton droit par défaut ; chaque geste peut utiliser un autre bouton) :

| Geste | Action |
|-------|--------|
| ↑ | Mission Control (⌃↑) |
| ↓ | Fenêtres des applications (⌃↓) |
| ↓← | Réduire la fenêtre |
| ↓→ | Fermer la fenêtre |
| ↑→ | Ouvrir Safari |
| →← | Lecture / pause |
| ↑← | Ouvrir GitHub |

## Fichier de configuration

Chemin :

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

Au quotidien, sélectionnez plusieurs éléments dans **Réglages → Gestes** pour exporter / importer des paquets JSON. Pour une sauvegarde complète, copiez le fichier ci-dessus ou éditez-le à la main (la structure doit rester valide). Les réglages peuvent **Afficher dans le Finder**.

## Pile technique

- Swift / SwiftUI (macOS 14+)
- MVVM + Service léger
- `CGEventTap` pour les événements souris / modificateur globaux
- Chargement runtime `dlopen` / `dlsym` de `MultitouchSupport` pour les gestes tactiles expérimentaux (pas de liaison statique)
- Persistance de configuration JSON
- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) pour l’ouverture à l’ouverture de session
- [Sparkle](https://github.com/sparkle-project/Sparkle) pour les mises à jour signées dans l’app
- XcodeGen pour le projet Xcode

## Licence et avertissement

Ce projet est sous [GNU Affero General Public License v3.0 (AGPL-3.0)](./LICENSE).

C’est un utilitaire local. La surveillance globale des événements et les actions de script sont puissantes. N’ajoutez que du Shell / AppleScript de confiance. L’auteur n’est pas responsable des mauvaises manipulations ni de l’abus d’autorisations.
