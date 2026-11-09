#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MESSAGE'
ABESS VPN — ancien installateur désactivé.

Ce dépôt contient l'application Android. Son ancien serveur a été retiré
car il contenait des identifiants de démonstration et des API historiques
non conformes au control plane actuel.

Aucune installation, mise à jour système ou modification du VPS n'a été effectuée.

Utilisez exclusivement le dépôt serveur dédié :
https://github.com/abesskamer237/AbessVpn-Server-Panel

Consultez son README et configurez les secrets de déploiement avant toute installation.
MESSAGE

exit 1
