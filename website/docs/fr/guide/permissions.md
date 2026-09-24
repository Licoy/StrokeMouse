---
title: "Autorisations"
description: "Autorisations StrokeMouse : Accessibilité pour l’écoute globale de la souris et du défilement, Automatisation pour AppleScript."
titleTemplate: "StrokeMouse"
---

# Autorisations

StrokeMouse a besoin d’une écoute souris globale et d’une automatisation facultative. Les échecs sont visibles dans la **barre des menus** et **Réglages → Autorisations**, pas silencieux.

## Vue d’ensemble

| Autorisation | Obligatoire ? | Usage |
|------------|-----------|---------|
| **Accessibilité** | **Oui** | Souris et défilement globaux (`CGEventTap`), injection de raccourcis, AX des fenêtres |
| **Automatisation** | Facultatif | AppleScript qui pilote d’autres apps |

## Accessibilité

### Pourquoi

Le moteur intercepte les séquences souris des **déclencheurs configurés**. Si `AXIsProcessTrusted()` est faux, l’app ne doit **pas** faire semblant d’écouter. Quand l’inversion ou le lissage est actif, le défilement amélioré utilise la même autorisation pour un écouteur limité à la molette. Sans confiance, le défilement reste natif.

### Comment activer

Préférez le flux **guide d’autorisation** intégré (premier lancement et **Réglages → Autorisations**) :

1. Cliquez **Guide d’autorisation** — ouvre **Confidentialité et sécurité → Accessibilité** et un panneau flottant qui suit la fenêtre des Réglages Système
2. Glissez **StrokeMouse** (les builds Debug apparaissent comme **StrokeMouse Dev**) du panneau vers la liste
3. Activez l’interrupteur ; l’app détecte la confiance en quelques secondes et démarre le moteur de gestes

Vous pouvez aussi faire les mêmes étapes manuellement dans Réglages Système.

### Cas fréquents

- **Mises à jour dans l’app des builds officiels** (identité auto-signée stable `StrokeMouse Release`) : l’Accessibilité n’a **en général pas** besoin d’être réaccordée
- **Migration depuis d’anciens builds ad-hoc, rotation du certificat ou nouveau chemin d’installation** : réautoriser **une fois**
- **Interrupteur allumé mais mort** : off/on, ou retirer et rajouter, puis relancer
- **Plusieurs copies** : autorisez le binaire que vous lancez vraiment

## Automatisation

Uniquement pour les actions **AppleScript** qui contrôlent d’autres apps. macOS demande au premier usage, par app cible.

## Sécurité

- Les taps d’événements globaux sont puissants — compilez ou téléchargez depuis des sources de confiance
- **Shell / AppleScript** ont le même pouvoir que votre utilisateur ; l’UI garde des avertissements — **n’ajoutez que des scripts de confiance**
- Politique d’ingénierie : ne pas dumper les scripts utilisateur complets dans des journaux publics

## Auto-contrôle

Si rien ne marche :

1. La barre des menus montre un problème d’autorisation / de moteur ?
2. L’Accessibilité est cochée pour **cette** instance de l’app ?
3. Les gestes sont en pause ?
4. Vous utilisez un bouton de souris qui **n’est pas** un déclencheur configuré ?

Voir aussi la [FAQ](./faq).
