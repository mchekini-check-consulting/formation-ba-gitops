# kargo-pipelines

Pipelines de promotion Kargo des dépôts métier : pour chaque dépôt, un Project,
un Warehouse (surveille les images ECR) et une Stage par environnement.

## Utilisé par

ApplicationSet `kargo-pipelines` (`gitops/templates/business/kargo-pipelines.yaml`),
une Application par projet (`business.projects` de `gitops/values.yaml`) :
`github`, `branch`, `registry` et `envs` viennent du bloc `business` de
`gitops/values.yaml` ; `access` de `values/common/access.yaml` ; `applications`
du `helm.yaml` du dépôt métier lui-même (source `$app` de l'Application).

## Fichiers (templates/)

| Fichier | Produit |
|---|---|
| `project.yaml` | Namespace, Project, ProjectConfig (promotion automatique), droits SSO, pour le projet courant |
| `warehouse.yaml` | Warehouse du projet courant, une souscription par application **avec une image** (`applications[].image` non vide) |
| `stages.yaml` | une Stage par environnement, pour le projet courant |
| `_helpers.tpl` | expression Kargo `${{ }}`, dépôt ECR d'un composant, droits SSO |

## Une promotion

1. clone de `main` du dépôt métier ;
2. écriture du tag de chaque composant **avec une image** dans `helm.yaml`
   (`applications.<index>.tag.<env>`, index = position dans `applications` du
   `helm.yaml` lui-même — toujours en phase, plus de liste à dupliquer dans
   gitops) ;
3. commit et push sur `main` ;
4. synchronisation de l'Application ArgoCD `<env>-<dépôt>`.

## Pièges

- Une application sans `image` dans `helm.yaml` (ex. `type: gateway`, fourni
  par la plateforme, rien à construire) est ignorée par ce chart : ni
  souscription Warehouse, ni tag à écrire. Si un composant a bien une image à
  construire, il doit avoir `image:` dans `helm.yaml`.
- `quote()` dans l'expression du tag : sans lui, un sha tout en chiffres
  (`7616898`) serait écrit en notation scientifique.
- L'ordre de `business.envs` est l'ordre de promotion.
