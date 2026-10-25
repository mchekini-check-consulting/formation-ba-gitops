# grafana-dashboards

Dashboards de logs de la plateforme, en lecture seule dans Grafana (dossier
`Logs`). Un ConfigMap par dashboard **activé**, chargé par le sidecar de Grafana
(`values/common/grafana.yaml`, `sidecar.dashboards`).

## Utilisé par

Application `grafana-dashboards` (namespace `logging`, wave 45), avec
`values/common/grafana-dashboards.yaml` et `values/<env>/grafana-dashboards.yaml`.

## Dashboards

Tous désactivés par défaut (`dashboards.<nom>.enabled: false`), activés par
environnement. Désactiver supprime le ConfigMap, donc le dashboard.

| Nom | Fichier | Données | Contenu |
|---|---|---|---|
| `http` | `dashboards/http.json` | Loki, `log_type="http_access"` et `"traefik"` | filtres Traefik (principal / gateways), environnement, projet, application, chemin ; requêtes totales, par environnement, par projet, par classe et par code HTTP, octets reçus / envoyés, endpoints (volume, 4xx, 5xx, p95), IPs clientes, réponses produites par un middleware, erreurs Traefik par middleware, logs d'accès |
| `business` | `dashboards/business.json` | Loki, `log_type="business"` | volume par couche (controller, service, db), erreurs par service, durée p95 par méthode, méthodes en erreur, requêtes base lentes ou en erreur |
| `infra` | `dashboards/infra.json` | Loki, `log_type="infra"` | critiques / erreurs, par source et par niveau, composants en erreur, motifs des événements Warning, nœuds |

Versions : 0.1.0 (initiale) ; 0.1.1 : dashboard HTTP par environnement / projet /
application / endpoint, gateways des projets et middlewares Traefik, variables
Loki corrigées (listes Environnement, Projet, Service du dashboard métier), section
control plane EKS (CloudWatch) retirée du dashboard infra.

Les labels `log_type`, `source`, `level`, `layer`, `env`, `project`, `application` sont posés par Alloy
(`values/common/alloy.yaml`, `alloy-events.yaml`).

## Modifier un dashboard

1. Le modifier dans Grafana (copie dans un dossier personnel : les dashboards
   provisionnés ne s'enregistrent pas), puis *Export > JSON*.
2. Remplacer `dashboards/<nom>.json` dans une **nouvelle version** du chart
   (`cp -r 0.1.0 0.1.1`, `version:` dans `Chart.yaml`), garder `uid` et les
   datasource `{"type": "loki", "uid": "loki"}`.
3. Monter `tools.grafana-dashboards.version` dans `gitops/values/<env>/cluster.yaml`.

## Tester

```bash
cd chart-base
helm template grafana-dashboards grafana-dashboards/0.1.1 -n logging \
  -f ../gitops/values/common/grafana-dashboards.yaml \
  -f ../gitops/values/dev/grafana-dashboards.yaml
```
