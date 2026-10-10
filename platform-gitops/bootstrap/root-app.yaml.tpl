# Application racine (app of apps), rendue et appliquée par bootstrap.sh.
# Elle rend charts/platform-apps avec clusters/${ENV}/platform.yaml comme values.
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
    path: ${GITOPS_PATH}/charts/platform-apps
    helm:
      valueFiles:
        - ../../clusters/${ENV}/platform.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
