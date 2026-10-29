# charts-ba-formations

Déploie les applications d'un dépôt métier (`formation-ba-<projet>`), décrites
dans le `helm.yaml` à la racine de ce dépôt. Une release par projet et par
environnement, dans le namespace `<env>-<projet>`.

## Utilisé par

L'ApplicationSet `gitops/templates/business/applicationset.yaml` : une Application
`<env>-<projet>` par couple (`business.envs` x `business.projects`), avec :

- `helm.yaml` du dépôt métier ;
- `gateway.yaml` du dépôt métier, optionnel (`ignoreMissingValueFiles: true`) ;
- `values/common/databases.yaml` + `values/<env>/databases.yaml` ;
- paramètres `env` et `project`.

Version utilisée : `business.charts.app` dans `gitops/values.yaml`.

## Fichiers (templates/)

| Fichier | Produit | Pour |
|---|---|---|
| `deployment.yaml` | Deployment | chaque application ayant un `tag` pour l'environnement (sinon ignorée, comme dans les autres fichiers sauf `database.yaml`) ; `tag`, `replicas`, `envList` par environnement. `type: gateway` : image Traefik fournie par la plateforme (pas de `tag` dans helm.yaml), config montée depuis `gateway-config.yaml` |
| `service.yaml` | Service `<application>` | chaque application |
| `ingress.yaml` | Ingress `<application>.<projet>.<env>.<domaine>` (+ Middleware strip) | frontends/gateways avec `ingress.enabled` |
| `gateway-config.yaml` | ConfigMap `<gateway>-config` : routes Traefik — `gatewayConfig` (de `gateway.yaml`, rendu avec `tpl`) si fourni, sinon une route par backend générée automatiquement (préfixe retiré, CORS pour les frontends) | applications `type: gateway` |
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
    tag:                          # écrit par Kargo ; vide = pas encore déployé
      dev: abc1234
      qualif: ""
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

## `gateway.yaml` (optionnel, racine du dépôt projet)

Pour personnaliser le routage/CORS/etc. du pod `gateway` au lieu du routage
généré automatiquement (routage, rate limiting, authentification
centralisée...), au format natif du "file provider" de Traefik :

```yaml
gatewayConfig: |
  http:
    routers:
      backend:
        rule: "PathPrefix(`/backend`)"
        service: backend
        middlewares: [backend-strip, cors]
    middlewares:
      backend-strip:
        stripPrefix: {prefixes: ["/backend"]}
      cors:
        headers:
          accessControlAllowOriginList:
            - https://frontend.{{ .project }}.{{ .env }}.{{ .domain }}
          accessControlAllowMethods: [GET, POST, PUT, PATCH, DELETE, OPTIONS]
    services:
      backend:
        loadBalancer: {servers: [{url: "http://backend:80"}]}
```

`gatewayConfig` est une **chaîne** (bloc `|`), rendue avec `tpl` : on peut y
écrire `{{ .project }}`/`{{ .env }}`/`{{ .domain }}`, une seule configuration
valant pour les 4 environnements (dev/qualif/preprod/prod) plutôt que d'en
écrire une copie par environnement.

## Tester

```bash
cd chart-base
helm dependency build charts-ba-formations/0.9.2
helm template formation-ba-scpi-invest charts-ba-formations/0.9.2 \
  -n dev-formation-ba-scpi-invest \
  -f ../../formation-ba-scpi-invest/helm.yaml \
  -f ../gitops/values/common/databases.yaml -f ../gitops/values/dev/databases.yaml \
  --set env=dev --set project=formation-ba-scpi-invest
```

## Pièges

- Un composant dont le `tag` est vide pour l'environnement n'est pas déployé
  dans cet environnement (ni Deployment, ni Service, ni Ingress, ni route du
  gateway par défaut) : c'est le cas d'un composant tout juste ajouté, tant que
  la CI n'a pas construit son image et que Kargo ne l'a pas promu. Sa base,
  elle, est créée dès l'ajout. Avec un `gateway.yaml`, sa route existe déjà et
  répond 502 jusqu'au déploiement. Jusqu'à 0.9.1, un tag vide faisait échouer
  le rendu de tout le projet.
- `tag` toujours en format bloc, une valeur par ligne (`dev: ""` sous `tag:`) :
  Kargo réécrit `applications.<index>.tag.<env>`, jamais un `{dev: "", ...}`
  sur une seule ligne.
- Un backend sans application `type: gateway` dans le même `helm.yaml` n'est
  joignable que depuis l'intérieur du cluster (Service ClusterIP).
