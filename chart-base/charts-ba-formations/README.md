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
| `deployment.yaml` | Deployment | chaque application ; `tag`, `replicas`, `envList` par environnement |
| `service.yaml` | Service `<application>` | chaque application |
| `ingress.yaml` | Ingress `<application>.<projet>.<env>.<domaine>` (+ Middleware strip) | frontends avec `ingress.enabled` |
| `gateway.yaml` | Ingress `api.<env>.<domaine>/<projet>/<application>`, Middlewares strip et CORS | backends avec `ingress.enabled` |
| `certificate.yaml` | Certificate `*.<projet>.<env>.<domaine>` | si au moins un frontend exposé |
| `database.yaml` | Cluster `app-db`, une base par application avec `database` (via pg-lib) | applications avec `database` |
| `_helpers.tpl` | valeur par environnement, labels, hosts, variables de connexion | |

## Clés de helm.yaml

```yaml
applications:
  - name: backend                 # nom du Deployment, du Service et de l'Ingress
    type: backend                 # backend : passerelle api.<env>... ; sinon host propre
    image: <registre>/<projet>/backend
    tag: {dev: abc1234, qualif: abc1234}   # écrit par Kargo
    containerPort: 8080
    replicas: {dev: 1, prod: 2}   # valeur unique ou map par environnement
    service: {port: 80}
    ingress: {enabled: true}      # frontend : host, path, stripPrefix possibles
    database: {name: ma_base}     # ou true (base = nom de l'application)
    envList:
      - key: LOG_LEVEL
        value: {dev: debug, prod: warn}
```

Variables injectées par `database` (avant `envList`) : `PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, `PGPASSWORD`, `DATABASE_URL`, `SPRING_DATASOURCE_URL`,
`SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`.

## Tester

```bash
cd chart-base
helm dependency build charts-ba-formations/0.6.0
helm template formation-ba-scpi-invest charts-ba-formations/0.6.0 \
  -n dev-formation-ba-scpi-invest \
  -f ../../formation-ba-scpi-invest/helm.yaml \
  -f ../gitops/values/common/databases.yaml -f ../gitops/values/dev/databases.yaml \
  --set env=dev --set project=formation-ba-scpi-invest
```

## Pièges

- Un `tag` vide pour l'environnement fait échouer le rendu : remplir `tag.<env>`
  avant d'ajouter un environnement.
- Le CORS de la passerelle n'autorise que les frontends du même `helm.yaml`.
- La passerelle `api.<env>` utilise le wildcard de la plateforme : un nouvel
  environnement doit y être ajouté (`values/dev/cert-manager.yaml`).
