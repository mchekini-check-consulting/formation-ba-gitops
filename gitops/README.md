# Bases PostgreSQL et sauvegardes

Toutes les bases (outils de la plateforme et projets métier) sont des Clusters
CloudNativePG, déclarés à **un seul endroit** : `values/common/databases.yaml`
(commun) et `values/<env>/databases.yaml` (environnement). Le rendu est fait par
le chart library `chart-base/pg-lib`, via :

- `pg-cluster` : base d'un outil (`tools.<outil>-db`, `databases: true` dans `values.yaml`) ;
- `charts-ba-formations` : base d'un projet métier (`database: true` sur une application de son `helm.yaml`).

Pour chaque cluster `<nom>` du namespace `<ns>` :

| Objet | Rôle |
|---|---|
| `Cluster <nom>` | PostgreSQL ; Secrets `<nom>-app` (propriétaire des bases) et `<nom>-superuser` si `superuser: true` |
| `Database <nom>-<base>` | une base logique ; retirée des values, elle n'est **pas** supprimée |
| `ObjectStore <nom>` | destination S3 `s3://<bucket>/<env>/<ns>/` |
| `ScheduledBackup <nom>` | sauvegarde physique complète planifiée (`backup.physical`) |
| `CronJob <nom>-dump-<base>` | `pg_dump` de la base (`backup.logical`, désactivé par défaut) |

`Cluster` et `Database` portent `Prune=false,Delete=false` : ArgoCD ne les
supprime jamais, même après une erreur de nom ou de chemin. Supprimer une base
est un geste manuel (`kubectl delete`), qui supprime aussi son disque.

## Sauvegardes dans S3

```
s3://<bucket>/<env>/<ns>/<archive>/base/...        sauvegardes complètes
s3://<bucket>/<env>/<ns>/<archive>/wals/...        WAL archivés en continu (PITR)
s3://<bucket>/<env>/<ns>/<nom>/dumps/<base>/...    dumps logiques
```

`<archive>` vaut `<nom>`, puis `<nom>-g<N>` après la N-ième restauration
(`generation`) : une base restaurée écrit toujours dans une archive neuve.

- Physique : restauration du cluster entier à n'importe quel instant de la
  fenêtre `backup.physical.retention` (7 jours par défaut).
- Logique : restauration base par base, au moment du dump.
- Bucket (Terraform `formation-ba-landingzone`, module `pg-backups`) : versioning,
  Object Lock 7 jours, versions supprimées conservées 30 jours, chiffrement KMS.

Vérifier :

```bash
# ARCHIVAGE doit être True ; False = WAL qui s'accumulent sur le disque de la base
kubectl get clusters.postgresql.cnpg.io -A -o custom-columns='NS:.metadata.namespace,NOM:.metadata.name,PHASE:.status.phase,ARCHIVAGE:.status.conditions[?(@.type=="ContinuousArchiving")].status'
kubectl get backups.postgresql.cnpg.io -A
aws s3 ls s3://<bucket>/<env>/ --recursive --summarize | tail -2
# Diagnostic d'un archivage en échec
kubectl -n <ns> logs <nom>-1 -c plugin-barman-cloud --tail=50
```

## Restaurer une base (en place)

Remet le cluster `<nom>` dans l'état d'un instant passé (ou du dernier WAL
archivé). Les applications gardent la même adresse (`<nom>-rw`).

Dans `databases.yaml` : `clusters.<nom>` pour un outil, `projects.<projet>`
pour un projet métier (le cluster s'appelle alors `app-db`).

**Étape 1 : commit** (generation = valeur actuelle + 1)

```yaml
databases:
  clusters:
    sonarqube-db:
      generation: 1
      restore:
        enabled: true
        targetTime: "2026-10-20T10:30:00Z"   # vide = dernier état archivé
```

Après la synchronisation, le cluster existant n'archive plus (pas d'écriture
dans l'ancienne archive, qui est la source) et sa sauvegarde planifiée est
retirée. Enchaîner rapidement avec l'étape 2 : les WAL non archivés
s'accumulent sur le disque.

**Étape 2 : manuelle**, supprimer le cluster (et son disque) ; ArgoCD le recrée
aussitôt, restauré depuis S3 :

```bash
kubectl -n sonarqube delete clusters.postgresql.cnpg.io sonarqube-db
kubectl -n sonarqube get clusters.postgresql.cnpg.io sonarqube-db -w   # jusqu'à "Cluster in healthy state"
```

Les mots de passe sont régénérés (Secrets `<nom>-app`, `<nom>-superuser`) :
redémarrer les applications qui les lisent, puis vérifier les données.

```bash
kubectl -n sonarqube rollout restart sts/sonarqube-sonarqube   # outil
kubectl -n dev-<projet> rollout restart deploy/backend          # projet métier
```

**Étape 3 : commit**, fin de la restauration (garder `generation`) :

```yaml
      generation: 1
      restore:
        enabled: false
```

Le cluster archive dans `<nom>-g1`, et une sauvegarde complète part aussitôt.
Vérifier `ARCHIVAGE = True` (commande plus haut).

Ne jamais supprimer un cluster sans l'étape 1 : ArgoCD le recréerait **vide**
(`initdb`), et il ne pourrait plus archiver (archive non vide).

L'ancienne archive (`<nom>` ou `<nom>-g<N-1>`) n'est plus nettoyée par la
rétention : la supprimer à la main une fois la restauration validée
(`aws s3 rm --recursive s3://<bucket>/<env>/<ns>/<ancienne archive>/`).

## Tester une restauration (sans toucher à la base)

Restaure une copie `<nom>-restore-db` dans le même namespace, sans archivage,
puis la supprime. Exemple avec sonarqube-db, depuis la racine du dépôt :

```bash
cat > /tmp/restore-test.yaml <<'EOF'
databases:
  clusters:
    sonarqube-restore-db:
      storage: 5Gi
      initdb: {database: sonarqube, owner: sonarqube}
      databases: {sonarqube: {}}
      restore:
        enabled: true
        from: sonarqube-db
        targetTime: ""            # ou un instant de la fenêtre de rétention
EOF
helm dependency build chart-base/pg-cluster/0.2.0
helm template sonarqube-restore-db chart-base/pg-cluster/0.2.0 -n sonarqube \
  -f gitops/values/common/databases.yaml -f gitops/values/dev/databases.yaml \
  -f /tmp/restore-test.yaml --set databases.env=dev \
  | yq 'select(.kind == "Cluster" or .kind == "ObjectStore")' > /tmp/restore-test-manifests.yaml
kubectl apply -f /tmp/restore-test-manifests.yaml
kubectl -n sonarqube get clusters.postgresql.cnpg.io sonarqube-restore-db -w
kubectl -n sonarqube exec sonarqube-restore-db-1 -c postgres -- \
  psql -d sonarqube -c "select count(*) from projects"
kubectl delete -f /tmp/restore-test-manifests.yaml
```

## Restaurer une seule base depuis un dump

```bash
aws s3 ls s3://<bucket>/<env>/<ns>/<nom>/dumps/<base>/
aws s3 cp s3://<bucket>/<env>/<ns>/<nom>/dumps/<base>/<horodatage>.dump ./base.dump
kubectl -n <ns> exec -i <nom>-1 -c postgres -- \
  pg_restore --clean --if-exists --no-owner --role=<propriétaire> -d <base> < ./base.dump
```
