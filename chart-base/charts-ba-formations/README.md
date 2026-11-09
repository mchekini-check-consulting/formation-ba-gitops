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
| `deployment.yaml` | Deployment | chaque application ayant un `tag` pour l'environnement (sinon ignorée, comme dans les autres fichiers sauf `database.yaml`) ; `tag`, `replicas`, `envList` par environnement. `type: gateway` : image Traefik fournie par la plateforme (pas de `tag` dans helm.yaml), config montée depuis `gateway-config.yaml`. `type: mailpit` : image Mailpit fournie par la plateforme (pas de `tag` non plus), deux ports (`smtp` 1025, `http` 8025) |
| `service.yaml` | Service `<application>` | chaque application ; `type: mailpit` : deux ports (`smtp` 1025, `http` 8025) au lieu d'un seul |
| `ingress.yaml` | Ingress `<application>.<projet>.<env>.<domaine>` (+ Middleware strip) | frontends/gateways/mailpit avec `ingress.enabled` (route vers le port `http` du Service) |
| `gateway-config.yaml` | ConfigMap `<gateway>-config` : routes Traefik — `gatewayConfig` (de `gateway.yaml`, rendu avec `tpl`) si fourni, sinon une route par backend générée automatiquement (préfixe retiré, CORS pour les frontends ; `mailpit` jamais ajouté aux origines CORS) | applications `type: gateway` |
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

  - name: mailpit                 # optionnel : serveur SMTP de test (voir plus bas)
    type: mailpit                 # pas d'image/tag à fournir (plateforme : Mailpit)
    ingress: {enabled: true}      # https://mailpit.<projet>.<env>.<domaine> (UI de consultation)
```

Variables injectées par `database` (avant `envList`) : `PGHOST`, `PGPORT`,
`PGDATABASE`, `PGUSER`, `PGPASSWORD`, `DATABASE_URL`, `SPRING_DATASOURCE_URL`,
`SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`.

## Variables prises dans un Secret (`envFrom`)

Pour donner à un composant les variables d'un Secret déjà présent dans son
namespace (`<env>-<projet>`, créé hors du chart, ex. clés d'accès S3) :

```yaml
  - name: backend
    type: backend
    envFrom:
      - secret: backend-s3
        optional: true   # pod démarré même si le Secret est absent de l'environnement
```

Chaque clé du Secret devient une variable du même nom (nom de variable valide
requis : `S3_BUCKET`, pas `s3.bucket`). Une variable de `database`/`envList`
de même nom l'emporte. Un Secret modifié n'est pris en compte qu'au
redémarrage du pod (`kubectl -n <env>-<projet> rollout restart deploy/<name>`).

## `type: mailpit` : serveur SMTP de test

Capture tous les e-mails envoyés par les autres applications du même projet
(dev/qualif), sans serveur SMTP réel ni authentification à configurer.
Comme `type: gateway`, fourni par la plateforme : pas d'`image`/`tag` à
donner dans `helm.yaml`, pas de build/CI/promotion Kargo pour ce composant.

```yaml
  - name: mailpit
    type: mailpit
    ingress: {enabled: true}   # UI de consultation : https://mailpit.<projet>.<env>.<domaine>
```

Les autres applications du projet lui envoient leurs e-mails via le Service
`mailpit` (nom court résolu dans le même namespace, donc valable seulement à
l'intérieur du même projet/environnement) :

```yaml
    envList:
      - key: SMTP_HOST
        value: mailpit
      - key: SMTP_PORT
        value: "1025"
```

Port `smtp` (1025, envoi) et port `http` (8025, UI web de lecture des
e-mails reçus) fixes, non configurables. Avec `ingress.enabled`, l'UI est
exposée exactement comme un frontend — même host que les autres applications
du projet (`<application>.<projet>.<env>.<domaine>`), même certificat
wildcard du projet (`certificate.yaml`) : pas de nom de domaine partagé à la
plateforme (à la différence d'un outil comme sonarqube/grafana, une seule
instance pour toute la plateforme), une instance et un host par projet.

Un seul réplica (`replicas` ignoré) : la boîte de réception vit en mémoire
dans le pod, pas de stockage partagé entre plusieurs instances.

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

### Plugins Traefik (authentification JWT)

Le pod gateway peut charger les plugins Traefik du catalogue `gatewayPlugins`
(`values.yaml` du chart, version épinglée par la plateforme). Un plugin n'est
activé (arguments `--experimental.plugins.<nom>.*`, téléchargement depuis
plugins.traefik.io au démarrage du pod) que si un middleware de `gateway.yaml`
l'utilise (`http.middlewares.<middleware>.plugin.<nom>`). Exemple, JWT émis par
le realm Keycloak des projets, `sub` et rôles transmis au backend en en-têtes :

```yaml
    routers:
      backend:
        rule: "PathPrefix(`/backend`)"
        service: backend
        middlewares: [cors, jwt, backend-strip]   # cors d'abord : preflight OPTIONS sans token
    middlewares:
      jwt:
        plugin:
          jwt:
            issuers:
              - https://keycloak.{{ .env }}.{{ .domain }}/realms/check-projects-sso
            require:
              azp: <client du frontend>
            headerMap:
              X-User-Sub: sub
              X-User-Roles: roles       # tableau -> JSON : ["admin","lecteur"]
            removeMissingHeaders: true  # X-User-* envoyés par le client jamais transmis
            forwardToken: false
```

Token absent ou invalide : 401, requête refusée par le gateway (le backend n'est
pas appelé) ; claim de `require` non satisfait : 403.

## Tester

```bash
cd chart-base
helm dependency build charts-ba-formations/0.9.4
helm template formation-ba-scpi-invest charts-ba-formations/0.9.4 \
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
