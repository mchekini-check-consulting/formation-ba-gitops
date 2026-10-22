#!/usr/bin/env bash
# Compare le rendu de deux versions d'un chart de chart-base, avec les mêmes values.
# À lancer avant de pointer gitops sur une nouvelle version : aucune différence
# affichée = même comportement dans le cluster.
#
#   [RELEASE=<nom>] ./scripts/compare-versions.sh <chart> <ancienne> <nouvelle> [arguments de helm template]
#
#   ./scripts/compare-versions.sh keycloak-config 0.3.0 0.3.1 -n keycloak \
#     -f ../gitops/values/common/access.yaml \
#     -f ../gitops/values/common/keycloak-config.yaml \
#     -f ../gitops/values/dev/keycloak-config.yaml
#
#   # pg-cluster : le nom de release est le nom de la base
#   RELEASE=sonarqube-db ./scripts/compare-versions.sh pg-cluster 0.2.0 0.2.1 -n sonarqube \
#     -f ../gitops/values/common/databases.yaml -f ../gitops/values/dev/databases.yaml \
#     --set databases.env=dev
#
# RELEASE : nom de release (défaut : nom du chart), comme le releaseName de
# l'Application ArgoCD. Clés triées et commentaires retirés (sans effet dans le
# cluster) ; le label helm.sh/chart, qui contient la version, est ignoré.
# Les chemins des -f sont relatifs à chart-base/. Prérequis : helm, yq (mikefarah v4).
set -euo pipefail

USAGE="usage: [RELEASE=<nom>] $0 <chart> <ancienne> <nouvelle> [arguments de helm template]"
CHART=${1:?$USAGE}
OLD=${2:?$USAGE}
NEW=${3:?$USAGE}
shift 3
RELEASE=${RELEASE:-$CHART}

cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Rendu normalisé d'une version dans $TMP/<version>.yaml ; arrêt si helm échoue
render() {
  local version=$1 dir="$CHART/$1"
  shift
  # Dépendances file:// (pg-lib) : charts/*.tgz non versionnés, reconstruits ici
  if grep -q '^dependencies:' "$dir/Chart.yaml"; then
    helm dependency build "$dir" >/dev/null
  fi
  helm template "$RELEASE" "$dir" "$@" > "$TMP/$version.raw"
  yq -P 'sort_keys(..) | ... comments=""' "$TMP/$version.raw" | grep -v 'helm.sh/chart:' > "$TMP/$version.yaml"
}

render "$OLD" "$@"
render "$NEW" "$@"
if diff -u --label "$CHART $OLD" --label "$CHART $NEW" "$TMP/$OLD.yaml" "$TMP/$NEW.yaml"; then
  echo "Rendu identique : $CHART $OLD -> $NEW ($(grep -c '^kind:' "$TMP/$NEW.yaml") objets)"
fi
