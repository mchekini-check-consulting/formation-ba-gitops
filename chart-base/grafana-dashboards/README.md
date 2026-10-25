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
| `http` | `dashboards/http.json` | Loki, `log_type="http_access"` | requêtes totales et par seconde, requêtes par classe et par code HTTP, octets reçus / envoyés, IPs clientes (top 20), requêtes par hôte |
| `business` | `dashboards/business.json` | Loki, `log_type="business"` | volume par couche (controller, service, db), erreurs par service, durée p95 par méthode, méthodes en erreur, requêtes base lentes ou en erreur |
| `infra` | `dashboards/infra.json` | Loki, `log_type="infra"` + CloudWatch | critiques / erreurs, par source et par niveau, composants en erreur, motifs des événements Warning, nœuds, control plane EKS (erreurs API server, accès refusés, actions sensibles de l'audit) |

Les labels `log_type`, `source`, `level`, `layer` sont posés par Alloy
(`values/common/alloy.yaml`, `alloy-events.yaml`) ; `infra` lit aussi
`eksLogGroup` (groupe CloudWatch du control plane, Terraform `eks`).

## Modifier un dashboard

1. Le modifier dans Grafana (copie dans un dossier personnel : les dashboards
   provisionnés ne s'enregistrent pas), puis *Export > JSON*.
2. Remplacer `dashboards/<nom>.json` dans une **nouvelle version** du chart
   (`cp -r 0.1.0 0.1.1`, `version:` dans `Chart.yaml`), garder `uid` et les
   datasources `{"type": "loki", "uid": "loki"}` / `{"type": "cloudwatch", "uid": "cloudwatch"}`.
3. Monter `tools.grafana-dashboards.version` dans `gitops/values/<env>/cluster.yaml`.

## Tester

```bash
cd chart-base
helm template grafana-dashboards grafana-dashboards/0.1.0 -n logging \
  -f ../gitops/values/common/grafana-dashboards.yaml \
  -f ../gitops/values/dev/grafana-dashboards.yaml
```
