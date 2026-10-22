# kargo-pipelines

Pipelines de promotion Kargo des dépôts métier : pour chaque dépôt, un Project,
un Warehouse (surveille les images ECR) et une Stage par environnement.

## Utilisé par

Application `kargo-pipelines` (`gitops/templates/business/kargo-pipelines.yaml`) :
`envs`, `projects`, `github`, `branch` et `registry` viennent du bloc `business`
de `gitops/values.yaml` ; `access` de `values/common/access.yaml`.

## Fichiers (templates/)

| Fichier | Produit |
|---|---|
| `project.yaml` | par dépôt : Namespace, Project, ProjectConfig (promotion automatique), droits SSO |
| `warehouse.yaml` | par dépôt : Warehouse, une souscription par composant |
| `stages.yaml` | par dépôt et environnement : Stage (alimentée par l'environnement précédent) |
| `_helpers.tpl` | expression Kargo `${{ }}`, dépôt ECR d'un composant, droits SSO |

## Une promotion

1. clone de `main` du dépôt métier ;
2. écriture du tag de chaque composant dans `helm.yaml`
   (`applications.<index>.tag.<env>`, index = position dans `components`) ;
3. commit et push sur `main` ;
4. synchronisation de l'Application ArgoCD `<env>-<dépôt>`.

## Pièges

- `components` (dans `business.projects`) suit l'ORDRE de `applications` du
  `helm.yaml` : réordonner l'un impose de réordonner l'autre.
- `quote()` dans l'expression du tag : sans lui, un sha tout en chiffres
  (`7616898`) serait écrit en notation scientifique.
- L'ordre de `business.envs` est l'ordre de promotion.
