# pg-cluster

Base PostgreSQL d'un outil de la plateforme (SonarQube, Keycloak, CloudBeaver).
Un seul template, qui appelle [pg-lib](../pg-lib/README.md).

## Utilisé par

`gitops/templates/platform/applications.yaml`, pour chaque outil déclaré avec
`chart: pg-cluster` et `databases: true` dans `gitops/values.yaml` :

- nom de l'Application = nom de la release = nom du Cluster = clé dans
  `databases.clusters` (ex. `sonarqube-db`) ;
- namespace = celui de l'outil ;
- values : `values/common/databases.yaml` + `values/<env>/databases.yaml`,
  paramètre `databases.env`.

## Ajouter une base d'outil

1. `gitops/values.yaml` : un bloc `tools.<outil>-db` (`chart: pg-cluster`,
   `databases: true`, `namespace`, `syncWave: "20"`, `finalizer: false`).
2. `gitops/values/<env>/cluster.yaml` : `tools.<outil>-db.version`.
3. `gitops/values/common/databases.yaml` : `databases.clusters.<outil>-db`
   (`initdb`, `databases`, `storage`...).

Rien à faire dans Terraform : le rôle de sauvegarde accepte tout Cluster `*-db`.

## Tester

```bash
cd chart-base
helm dependency build pg-cluster/0.2.0
helm template sonarqube-db pg-cluster/0.2.0 -n sonarqube \
  -f ../gitops/values/common/databases.yaml -f ../gitops/values/dev/databases.yaml \
  --set databases.env=dev
```
