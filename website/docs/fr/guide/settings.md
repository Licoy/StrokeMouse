---
title: "Réglages et barre des menus"
description: "Réglages StrokeMouse et barre des menus : bibliothèque de gestes, inversion et lissage du défilement, recherche/filtre/import-export, éditeur, apparence, ouverture de session et autorisations."
titleTemplate: "StrokeMouse"
---

# Réglages et barre des menus

## Barre des menus

Contrôles du quotidien :

- **Démarrer / arrêter les gestes**
- **Suspendre / reprendre le défilement amélioré** — apparaît dès qu’une fonction de défilement est activée, indépendamment de la pause des gestes
- **Ouvrir les réglages**
- **Teinte d’état** — normal ; **jaune** si les gestes sont en pause ; **rouge** si l’Accessibilité manque
- **Quitter**

En option : ouverture à l’ouverture de session, icône Dock masquée et **icône de barre des menus masquée**. Avec l’icône de menu masquée, cliquez StrokeMouse dans le Dock ou relancez l’app pour ouvrir les réglages ; si le Dock est aussi masqué, relancez l’app. Les réglages généraux peuvent restaurer l’icône de menu et **quitter l’app**.

Masquer à la fois Dock et barre des menus demande une confirmation pour ne pas perdre tous les points d’entrée visibles.

## Sections des réglages

| Section | Contenu |
|---------|---------|
| **Gestes** | Barre latérale (global / par app) + liste : recherche / filtre / opérations groupées, import/export, éditeur |
| **Défilement** | Inversion par axe, lissage de la molette crantée, exclusions selon l’app au premier plan ; reste sur ce Mac |
| **Général** | Apparence, élément d’ouverture de session, masquer Dock / barre des menus, quitter |
| **Autorisations** | État Accessibilité / Automatisation, guide d’autorisation, liens profonds |
| **À propos** | Version et infos produit |

## Défilement amélioré {#scroll-enhancement}

**Réglages → Défilement** est séparé des gestes. Le « défilement naturel » du système reste un seul interrupteur partagé par la souris et le trackpad. Ici, vous pouvez inverser encore une fois par appareil et par axe, et donner de l’inertie à une molette crantée.

- L’**interrupteur général** est activé par défaut, l’inversion et le lissage sont désactivés. Tant qu’aucune fonction n’est activée, aucun écouteur de défilement n’est installé et les gestes existants ne changent pas
- L’**inversion** sépare la molette du trackpad et de la Magic Mouse, chacun avec verticale et horizontale. Elle s’ajoute au défilement naturel. Inverser l’horizontale du trackpad peut affecter le balayage pour changer de page dans les navigateurs. Le défilement horizontal avec Shift suit le réglage vertical
- Le **défilement fluide** ne concerne qu’une molette crantée, pas le trackpad ni une molette haute résolution sans phase de geste. Les préréglages sont Doux, Standard et Réactif. Déplacer la vitesse, la durée ou l’accélération dans Avancé passe en Personnalisé. La vitesse et l’accélération ne s’appliquent que si le lissage est actif. Maintenir Command, Option, Control ou Shift conserve le défilement natif
- Les **apps exclues** correspondent à l’**app au premier plan**, pas à la fenêtre sous le pointeur. Utile pour les jeux, les bureaux distants, les machines virtuelles, et les apps qui ne lisent que des pas entiers et défilent trop peu avec le lissage
- Mettre les gestes en pause ne met pas le défilement en pause, et vous pouvez l’essayer avec les réglages ouverts. Dès qu’une fonction est activée, la barre des menus propose de suspendre ou reprendre le défilement amélioré. L’icône de la barre des menus ne reflète toujours que l’état des gestes
- Ces réglages restent sur ce Mac. Ils n’entrent pas dans l’export des gestes, `gestures.json`, ni la synchro de sauvegarde. Un autre outil de défilement peut traiter les événements deux fois

L’écoute du défilement exige aussi l’Accessibilité. Sans elle, le défilement reste natif, et **Réglages → Autorisations** affiche son état sur une ligne séparée.

## Liste des gestes

- La barre latérale gauche groupe par **Global** et **apps à portée** (proche des portées de raccourcis système) ; **Nouveau** sous une app préremplit cette portée
- Nom, déclencheur, action, **portée (globale ou icônes d’app)**, état activé
- **Recherche** par nom / action / notes ; filtre **Tous / Activés / Désactivés** ; tri des colonnes
- Créer / modifier / supprimer ; **multi-sélection** pour activer, désactiver, supprimer ou exporter en lot
- **Import / export** de paquets JSON : exporter la sélection ; à l’import, ignorer les doublons ou les importer de force (les doublons forcés sont désactivés par défaut)
- Les valeurs par défaut sont modifiables et supprimables

## Éditeur de gestes

Champs typiques d’un profil :

1. **Nom** et notes
2. **Déclencheur**
3. **Chemin** — enregistrer des points de trajectoire libre (ou des modèles directionnels)
4. **Action** — voir [Actions](./actions)
5. **Portée** — globale, ou ajouter des apps par icône (rechercher les apps installées / multi-sélection / parcourir un `.app` ; stocké comme bundle ids)
6. **Activé**

Maintenez le déclencheur pour enregistrer ; relâchez pour terminer. Réenregistrez jusqu’à satisfaction.

## Thème et langue

- Apparence : suivre le système ou forcer clair / sombre
- Textes : anglais, chinois simplifié, chinois traditionnel, coréen, japonais, russe et français (ou langue du système)

## Première ouverture

Le premier lancement peut afficher un court guide. Les autorisations et ce site restent la référence à long terme.

## Sauvegarde et partage

- **Au quotidien** : Réglages → Gestes → exporter la sélection en JSON ; importer sur un autre Mac
- **Bibliothèque complète** : **Afficher dans le Finder** pour copier `gestures.json`. Voir [Fichier de config](./config-file)
