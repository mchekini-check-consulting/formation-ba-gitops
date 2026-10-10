#!/usr/bin/env bash
# Installe ArgoCD puis lui confie la plateforme.
#
#   ./bootstrap.sh dev        -> lit clusters/dev/platform.yaml
#
# Après ce script, ArgoCD se gère lui-même : une mise à jour = changer la
# version dans platform.yaml (+ sync-crds.sh / sync-charts.sh si la version
# est nouvelle).
#
# Prérequis : kubectl (connecté au bon cluster), helm, yq (mikefarah v4)
# Dépôt privé : exporter GITHUB_TOKEN avant de lancer le script.
set -euo pipefail

ENV=${1:?usage: $0 <env>}

GITOPS_DIR=$(cd "$(dirname "$0")/.." && pwd)
PLATFORM="$GITOPS_DIR/clusters/$ENV/platform.yaml"

# Lecture de clusters/<env>/platform.yaml
CLUSTER=$(yq .cluster.name "$PLATFORM")
VERSION=$(yq .tools.argocd.version "$PLATFORM")
REPO_URL=$(yq .gitops.repoURL "$PLATFORM")
REVISION=$(yq .gitops.targetRevision "$PLATFORM")
GITOPS_PATH=$(yq .gitops.path "$PLATFORM")

# Garde-fou : on ne bootstrappe que le cluster de l'environnement
if [[ "$(kubectl config current-context)" != *"$CLUSTER"* ]]; then
  echo "ERREUR: kubectl n'est pas connecté à $CLUSTER" >&2
  echo "  aws eks update-kubeconfig --region $(yq .cluster.region "$PLATFORM") --name $CLUSTER" >&2
  exit 1
fi

echo "==> 1/3 CRDs ArgoCD $VERSION (crd-base)"
kubectl apply --server-side -k "$GITOPS_DIR/../crd-base/argocd/$VERSION"

echo "==> 2/3 ArgoCD $VERSION (helm depuis chart-base, sans CRDs)"
# Même release / chart / values que l'Application argocd qui prend le relais
helm upgrade --install argocd "$GITOPS_DIR/../chart-base/argocd/$VERSION" \
  --namespace argocd --create-namespace \
  --skip-crds --set crds.install=false \
  -f "$GITOPS_DIR/values/common/argocd.yaml" \
  -f "$GITOPS_DIR/values/$ENV/argocd.yaml" \
  --wait

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "==> Accès au dépôt privé $REPO_URL"
  kubectl -n argocd create secret generic repo-platform-gitops \
    --from-literal=type=git --from-literal=url="$REPO_URL" \
    --from-literal=username=git --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
  | kubectl apply -f -
fi

echo "==> 3/3 Application racine platform-root"
sed -e "s|\${ENV}|$ENV|g" \
    -e "s|\${REPO_URL}|$REPO_URL|g" \
    -e "s|\${TARGET_REVISION}|$REVISION|g" \
    -e "s|\${GITOPS_PATH}|$GITOPS_PATH|g" \
    "$GITOPS_DIR/bootstrap/root-app.yaml.tpl" \
| kubectl apply -f -

echo "OK. Suivi : kubectl -n argocd get applications -w"
