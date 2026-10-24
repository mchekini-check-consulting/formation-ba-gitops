# charts-ba-formations

Déploie les applications d'un dépôt métier (`formation-ba-<projet>`), décrites
dans le `helm.yaml` à la racine de ce dépôt. Une release par projet et par
environnement, dans le namespace `<env>-<projet>`.

## Utilisé par

L'ApplicationSet `gitops/templates/business/applicationset.yaml` : une Application
`<env>-<projet>` par couple (`business.envs` x `business.projects`), avec :

- `helm.yaml` du dépôt métier ;
- `values/common/databases.yaml` + `values/<env>/databases.yaml` ;
- paramètres `env` et `project`.

Version utilisée : `business.charts.app` dans `gitops/values.yaml`.

## Fichiers (templates/)

| Fichier | Produit | Pour |
|---|---|---|
| `deployment.yaml` | Deployment | chaque application ; `tag`, `replicas`, `envList` par environnement. `type: gateway` : image Traefik fournie par la plateforme (pas de `tag` dans helm.yaml), config montée depuis `gateway-config.yaml` |
| `service.yaml` | Service `<application>` | chaque application |
| `ingress.yaml` | Ingress `<application>.<projet>.<env>.<domaine>` (+ Middleware strip) | frontends/gateways avec `ingress.enabled` |
| `gateway-config.yaml` | ConfigMap `<gateway>-config` : routes Traefik (une par backend, préfixe retiré, CORS pour les frontends) | applications `type: gateway` |
| (aucun) | pas d'Ingress direct pour les backends : Service ClusterIP seulement, exposé par le pod gateway du projet (s'il en a un) | `type: backend` |
| `certificate.yaml` | Certificate `*.<projet>.<env>.<domaine>` | si au moins un frontend/gateway exposé |
| `database.yaml` | Cluster `app-db`, une base par application avec `database` (via pg-lib) | applications avec `database` |
| `_helpers.tpl` | valeur par environnement, labels, hosts, variables de connexion | |

## Clés de helm.yaml

```yaml
applications:
  - name: backend                 # nom du Deployment et du Service
    type: backend                 # backend : jamais d'Ingress direct ; sinon host propre
    image: <registre>/<projet>/backend
    tag: {dev: abc1234, qualif: abc1234}   # écrit par Kargo
    containerPort: 8080
    replicas: {dev: 1, prod: 2}   # valeur unique ou map par environnement
    service: {port: 80}
    database: {name: ma_base}     # ou true (base = nom de l'application)
    envList:
      - key: LOG_LEVEL
        value: {dev: debug, prod: warn}

  - name: gateway                 # un par projet, optionnel : expose les backends ci-dessus
    type: gateway                 # pas d'image/tag à fournir (plateforme : Traefik)
    replicas: {dev: 1, prod: 2}
    ingress: {enabled: true}      # https://gateway.<projet>.<env>.<domaine>/<backend>/...
```

Variables injectées par `database` (avant `envList`) : `PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, `PGPASSWORD`, `DATABASE_URL`, `SPRING_DATASOURCE_URL`,
`SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`.

## Tester

```bash
cd chart-base
helm dependency build charts-ba-formations/0.8.0
helm template formation-ba-scpi-invest charts-ba-formations/0.8.0 \
  -n dev-formation-ba-scpi-invest \
  -f ../../formation-ba-scpi-invest/helm.yaml \
  -f ../gitops/values/common/databases.yaml -f ../gitops/values/dev/databases.yaml \
  --set env=dev --set project=formation-ba-scpi-invest
```

## Pièges

- Un `tag` vide pour l'environnement fait échouer le rendu : remplir `tag.<env>`
  avant d'ajouter un environnement (ne s'applique pas à `type: gateway`, qui n'a
  pas de `tag`).
- Un backend sans application `type: gateway` dans le même `helm.yaml` n'est
  joignable que depuis l'intérieur du cluster (Service ClusterIP).
