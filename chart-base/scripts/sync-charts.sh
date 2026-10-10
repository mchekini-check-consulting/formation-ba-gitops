#!/usr/bin/env bash
# Copie un chart Helm (dépendances comprises) dans chart-base/<outil>/<version>/.
# ArgoCD et bootstrap.sh installent le chart depuis ce dossier, plus depuis
# le dépôt Helm upstream.
#
#   ./scripts/sync-charts.sh argocd 10.9.6
#
# Prérequis : helm, yq (mikefarah v4)
set -euo pipefail

TOOL=${1:?usage: $0 <outil> <version>}
VERSION=${2:?usage: $0 <outil> <version>}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/$TOOL/$VERSION"

# Une version publiée ne change plus
if [[ -e "$DEST" ]]; then
  echo "ERREUR: $TOOL/$VERSION existe déjà (immuable)" >&2
  exit 1
fi

# Lecture du catalogue
REPO=$(yq ".tools.$TOOL.repo" "$ROOT/catalog.yaml")
CHART=$(yq ".tools.$TOOL.chart" "$ROOT/catalog.yaml")
if [[ "$CHART" == "null" ]]; then
  echo "ERREUR: $TOOL absent de catalog.yaml" >&2
  exit 1
fi

# Téléchargement + décompression dans un dossier temporaire,
# puis le contenu du chart va directement dans <outil>/<version>/
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
helm pull "$CHART" --repo "$REPO" --version "$VERSION" --untar --untardir "$TMP"

mkdir -p "$(dirname "$DEST")"
mv "$TMP/$CHART" "$DEST"

echo "OK: chart $CHART $VERSION dans $TOOL/$VERSION"
