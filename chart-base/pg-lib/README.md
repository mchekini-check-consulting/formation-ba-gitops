# pg-lib (chart library)

Ne produit rien seul. Rend tous les objets d'une base PostgreSQL CloudNativePG et
de ses sauvegardes, pour les deux charts qui l'appellent : `pg-cluster` (bases des
outils) et `charts-ba-formations` (bases des projets métier). Une base ne peut
donc pas exister sans sa configuration de sauvegarde.

Déclaration des bases : `gitops/values/common/databases.yaml` (+ `values/<env>/databases.yaml`).
Procédures (restauration, vérifications) : `gitops/README.md`.

## Utilisation par un chart

```yaml
{{- $ctx := include "pg-lib.config" (dict
      "Values" .Values           # doit contenir databases
      "name" "sonarqube-db"      # nom du Cluster, doit finir par -db
      "namespace" .Release.Namespace
      "cluster" "sonarqube-db"   # clé de databases.clusters (ou "project" : clé de databases.projects)
    ) | fromYaml }}
{{- include "pg-lib.all" $ctx }}
```

## Fichiers (templates/)

| Fichier | Contenu |
|---|---|
| `_config.tpl` | `pg-lib.config` : fusion `defaults` < surcharge du cluster, garde-fous, archive S3 (`generation`), source de restauration ; `pg-lib.merge` ; labels |
| `_all.tpl` | `pg-lib.all` : décide quels objets rendre (seul point d'entrée) |
| `_cluster.tpl` | le Cluster CNPG (initdb ou recovery, archivage WAL) |
| `_backup.tpl` | ObjectStore (destination S3) et ScheduledBackup |
| `_database.tpl` | une Database par base logique |
| `_dump.tpl` | CronJob `pg_dump` -> S3 (sauvegarde logique, désactivée par défaut) |

## Objets produits

| Objet | Quand | Protégé contre la suppression ArgoCD |
|---|---|---|
| ObjectStore `<nom>` | sauvegarde physique ou restauration | non (sans données) |
| Cluster `<nom>` | toujours | oui (`Prune=false,Delete=false`) |
| ScheduledBackup `<nom>` | sauvegarde physique, hors restauration | non |
| Database `<nom>-<base>` | une par base | oui |
| CronJob `<nom>-dump-<base>` | `backup.logical.enabled` | non |

## Pièges

- `bootstrap` (initdb / recovery) n'est lu qu'à la **création** du Cluster.
- `pg-lib.merge` et non `mergeOverwrite` : avec sprig, `false` et `0` ne
  surchargent pas (ex. `enablePDB: false` en dev serait ignoré).
- Changer `defaults.imageName` de version majeure monte la version de **toutes**
  les bases.
- Toute modification passe par une nouvelle version de pg-lib, puis de pg-cluster
  et de charts-ba-formations (qui la référencent dans leur `Chart.yaml`).
