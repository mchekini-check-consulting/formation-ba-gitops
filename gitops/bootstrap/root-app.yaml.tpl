# Application racine (app of apps), rendue et appliquée par bootstrap.sh.
# Elle rend le chart gitops/ avec values/${ENV}/cluster.yaml comme values :
# Applications des outils (templates/platform) et des projets métier (templates/business).
# Sans finalizer : la supprimer ne supprime pas les Applications qu'elle a créées.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: ${TARGET_REVISION}
    path: ${GITOPS_PATH}
    helm:
      valueFiles:
        - values/${ENV}/cluster.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
