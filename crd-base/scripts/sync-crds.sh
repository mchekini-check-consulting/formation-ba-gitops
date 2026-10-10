#!/usr/bin/env bash
# Copie les CRDs d'un chart Helm dans crd-base/<outil>/<version>/
# (une CRD par fichier + kustomization.yaml).
#
#   ./scripts/sync-crds.sh argocd 10.9.6
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
SET=$(yq ".tools.$TOOL.set // \"\"" "$ROOT/catalog.yaml")
if [[ "$CHART" == "null" ]]; then
  echo "ERREUR: $TOOL absent de catalog.yaml" >&2
  exit 1
fi

# 1. Rendu du chart, on ne garde que les CRDs
CRDS=$(helm template crds "$CHART" --repo "$REPO" --version "$VERSION" \
         --include-crds ${SET:+--set "$SET"} \
       | yq 'select(.kind == "CustomResourceDefinition")')

# 2. Un fichier par CRD : <nom>.yml
mkdir -p "$DEST"
cd "$DEST"
echo "$CRDS" | yq -s '.metadata.name + ".yml"' -

# 3. kustomization.yaml qui liste les fichiers
{
  echo "# Généré par scripts/sync-crds.sh $TOOL $VERSION - NE PAS MODIFIER"
  echo "apiVersion: kustomize.config.k8s.io/v1beta1"
  echo "kind: Kustomization"
  echo "resources:"
  ls *.yml | sed 's/^/  - /'
} > kustomization.yaml

echo "OK: $(ls *.yml | wc -l) CRD(s) dans $TOOL/$VERSION"
