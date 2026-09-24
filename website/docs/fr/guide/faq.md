---
title: "FAQ"
description: "FAQ StrokeMouse : gestes inactifs, menu clic droit, faux positifs, autorisations, sauvegardes import/export."
titleTemplate: "StrokeMouse"
---

# FAQ

## Les gestes ne font rien ?

Vérifiez dans l’ordre :

1. **Accessibilité** pour **cette** copie de l’app (changement de chemin, rotation de certificat ou migration ad-hoc → auto-signé : réaccorder ; les mises à jour de la même identité officielle généralement pas)
2. État de la barre des menus pour pause ou erreurs d’autorisation
3. Geste **activé**
4. Vous maintenez le **déclencheur** configuré (droit par défaut, pas gauche)
5. Trait assez long (les clics courts se rejouent comme des clics normaux)

Voir [Autorisations](./permissions) et [Démarrage rapide](./getting-started).

## Le menu clic droit a disparu ?

Un clic droit court (presque pas de glisser) doit encore ouvrir le menu. Une fois la distance min dépassée, les événements sont réservés au geste — c’est voulu.

Utilisez des clics légers pour les menus ; dessinez assez long pour les gestes. Ou liez les gestes aux boutons **milieu / latéraux** et laissez le clic droit au système.

## Mauvais geste ou trop de faux positifs ?

- Différenciez les chemins similaires
- Désactivez les candidats inutiles sur le même déclencheur
- Réenregistrez des modèles plus propres
- Restreignez avec la portée d’app

## Trop strict / trop souple ?

La correspondance utilise des seuils de score et des portes structurelles. Trop strict : réenregistrez plus près du modèle ; trop souple : changez la forme des modèles, retirez les sosies.

## Les actions de fenêtre échouent ?

Confirmez l’Accessibilité. Certaines apps exposent un arbre AX faible — essayez une action raccourci équivalente.

## Shell / AppleScript silencieux ?

- La commande / le script marche seul dans Terminal / Éditeur de scripts ?
- Pour piloter d’autres apps, l’**Automatisation** est accordée ?
- Une invite système est-elle cachée derrière des fenêtres ?

## Vous avez masqué l’icône de la barre des menus ?

Cliquez StrokeMouse dans le Dock (si l’icône Dock est encore visible), ou relancez l’app — les réglages s’ouvrent. Sous **Réglages → Général** vous pouvez réafficher l’icône de menu ou quitter. Si Dock et barre des menus sont tous deux masqués, relancez l’app pour atteindre les réglages.

## Pas d’ouverture à l’ouverture de session ?

Activez dans **Réglages → Général**. Vérifiez aussi **Réglages Système → Éléments d’ouverture** si macOS l’a désactivé.

## Mauvais clair / sombre ?

Forcez l’apparence sous Général, ou revenez à « suivre le système ».

## Config perdue ?

Vérifiez `~/Library/Application Support/StrokeMouse/gestures.json`. Restaurez depuis une sauvegarde après avoir quitté l’app. Si vous n’avez qu’un paquet JSON exporté, utilisez **Réglages → Gestes → Importer**. Voir [Fichier de config](./config-file).

## Quelle souris faut-il ?

N’importe quelle souris avec un bouton déclencheur utilisable. Par défaut le bouton **droit** ; changez par geste vers milieu ou latéral. Les clics trackpad peuvent servir de boutons souris ; les gestes multi-doigts du trackpad ne sont pas le flux principal de ce produit. Le défilement amélioré n’exige pas une souris précise ; seule une molette crantée peut être lissée.

## Le sens ou le ressenti du défilement est faux ?

- L’inversion s’ajoute au « défilement naturel » du système. La molette et le trackpad (y compris Magic Mouse) se règlent séparément
- Le lissage ne concerne qu’une molette crantée. Le trackpad et une molette haute résolution sont seulement inversés, pas lissés
- Maintenir Command, Option, Control ou Shift désactive le lissage
- Une app exclue au premier plan n’est pas traitée. L’exclusion suit l’app au premier plan, pas la fenêtre sous le pointeur
- Un autre outil de défilement peut traiter les événements deux fois
- Ces réglages ne suivent pas la sauvegarde des gestes. Sur un autre Mac, réglez-les de nouveau dans **Réglages → Défilement**

Voir [Réglages et barre des menus](./settings#scroll-enhancement).

## Comment sauvegarder / partager des gestes ?

- **Quelques gestes** : Réglages → Gestes → multi-sélection → **Exporter** JSON ; **Importer** sur un autre Mac (ignorer ou forcer les doublons)
- **Bibliothèque complète** : copier `~/Library/Application Support/StrokeMouse/` ou seulement `gestures.json` ; restaurer après install + autorisation

Voir [Fichier de config](./config-file) et [Réglages et barre des menus](./settings).
