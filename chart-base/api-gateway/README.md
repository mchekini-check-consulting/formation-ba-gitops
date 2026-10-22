# api-gateway

Passerelle API d'un environnement, faite avec Traefik seul : **un** IngressRoute
sur `api.<env>.check-consulting.net`, qui route vers les Services ClusterIP des
backends métier. Les backends n'ont aucun Ingress.

```
https://api.dev.check-consulting.net/formation-ba-scpi-invest/backend/items
  -> Service backend (ClusterIP), namespace dev-formation-ba-scpi-invest, requête /items
```

## Utilisé par

`gitops/templates/business/api-gateway.yaml` : une Application `api-gateway-<env>`
par environnement de `business.envs`, namespace `api-gateway-<env>`, projet ArgoCD
de la plateforme. Version : `business.charts.gateway` dans `gitops/values.yaml`.

## Ce qu'il produit

| Objet | Rôle |
|---|---|
| IngressRoute `api-gateway` | une route par backend : `Host(api.<env>)` et chemin `/<projet>/<backend>` -> Service `<backend>` (port `http`) du namespace `<env>-<projet>` |
| Middleware `strip` | retire `/<projet>/<backend>` avant le backend |
| Middleware `cors` | autorise les frontends de l'environnement (`https://<composant>.<projet>.<env>...`) |

Un chemin non déclaré reçoit une 404 de Traefik.

## Exposer un backend

Dans `gitops/values.yaml`, `business.projects` :

```yaml
    - name: formation-ba-scpi-invest
      components: [backend, frontend]
      api: [backend]        # backends routés par la passerelle
```

Un backend absent de `api` reste joignable seulement dans le cluster.

## Prérequis plateforme

- Traefik : `providers.kubernetesCRD.allowCrossNamespace: true`
  (`values/common/traefik.yaml`), pour router vers d'autres namespaces. Les projets
  métier ne peuvent pas créer d'IngressRoute (liste blanche de leurs AppProjects).
- DNS : un IngressRoute ne porte pas l'adresse du NLB ; `api.<env>` est publié par
  external-dns (source `service`) depuis l'annotation
  `external-dns.alpha.kubernetes.io/hostname` du Service de Traefik
  (`values/<env>/traefik.yaml`).
- Certificat : wildcard `*.<env>.check-consulting.net` de la plateforme
  (`values/dev/cert-manager.yaml`), servi par défaut par Traefik (`tls: {}`).

Nouvel environnement sur ce cluster : ajouter `api.<env>` à l'annotation du
Service de Traefik et `*.<env>` au wildcard.

## Tester

```bash
cd chart-base
helm template api-gateway-dev api-gateway/0.1.0 -n api-gateway-dev \
  --set env=dev \
  --set 'projects[0].name=formation-ba-scpi-invest' \
  --set 'projects[0].components={backend,frontend}' \
  --set 'projects[0].api={backend}'
```
