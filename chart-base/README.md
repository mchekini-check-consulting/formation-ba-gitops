# chart-base

Tous les charts Helm déployés par ArgoCD, un dossier par version :
`chart-base/<chart>/<version>/`. ArgoCD lit uniquement ce dossier, jamais un
dépôt Helm en ligne.

## Deux sortes de charts

| Sorte | Charts | Origine | On modifie ? |
|---|---|---|---|
| Téléchargés | argocd, traefik, external-dns, cert-manager, falco, cloudnative-pg, plugin-barman-cloud, sonarqube, kargo, keycloakx | dépôt Helm de l'éditeur, copié par `scripts/sync-charts.sh` (source : `catalog.yaml`) | jamais : on règle tout par les values (`gitops/values`) |
| Maison | voir tableau ci-dessous | écrits ici | oui, en créant une nouvelle version |

| Chart maison | Rôle | Utilisé par |
|---|---|---|
| [pg-lib](pg-lib/README.md) | bibliothèque : base PostgreSQL + sauvegardes S3 | pg-cluster, charts-ba-formations |
| [pg-cluster](pg-cluster/README.md) | base d'un outil de la plateforme | Applications `<outil>-db` |
| [charts-ba-formations](charts-ba-formations/README.md) | applications des projets métier (Deployment, Service, Ingress, base) | ApplicationSet métier |
| [kargo-pipelines](kargo-pipelines/README.md) | promotion des images entre environnements | Application `kargo-pipelines` |
| [keycloak-config](keycloak-config/README.md) | realms, clients, groupes, utilisateurs Keycloak | Application `keycloak-config` |
| [sonarqube-config](sonarqube-config/README.md) | groupes et permissions SonarQube | Application `sonarqube-config` |
| [cloudbeaver](cloudbeaver/README.md) | CloudBeaver (pas de chart officiel) | Application `cloudbeaver` |

## Règles

1. **Une version publiée ne change plus.** Toute modification = nouveau dossier
   (`cp -r 0.3.0 0.3.1`, puis `version:` dans `Chart.yaml`). Raison : ArgoCD peut
   toujours revenir à une version connue, et deux environnements peuvent tourner sur
   deux versions différentes.
2. **La version déployée se choisit dans gitops**, jamais ici :
   - outils : `gitops/values/<env>/cluster.yaml` (`tools.<outil>.version`)
   - projets métier : `gitops/values.yaml` (`business.charts.app`, `business.charts.pipelines`)
3. **Avant de changer de version, comparer le rendu** avec les vraies values :
   ```bash
   cd chart-base
   ./scripts/compare-versions.sh keycloak-config 0.3.0 0.3.1 -n keycloak \
     -f ../gitops/values/common/access.yaml \
     -f ../gitops/values/common/keycloak-config.yaml \
     -f ../gitops/values/dev/keycloak-config.yaml
   ```
   Aucune différence = même comportement. Sinon, chaque ligne `-`/`+` est un
   changement réel dans le cluster : à comprendre avant de merger.
4. **Supprimer une ancienne version** seulement quand plus rien ne la référence
   (`grep -rn "<chart>/<version>" ..`), et jamais celle encore déployée sur `main`.
5. **Dépendance à pg-lib** (`file://../../pg-lib/<version>`) : le `.tgz` dans
   `charts/` n'est pas versionné ; ArgoCD le reconstruit, en local :
   `helm dependency build <chart>/<version>`.

## Écrire un template lisible

- Un fichier par sujet ; les `_*.tpl` ne contiennent que des `define`.
- Décrire les objets en YAML, avec des `{{ if }}` / `{{ range }}`, plutôt que de les
  construire à coups de `dict` / `set` : le fichier doit ressembler au résultat.
- Commenter en tête de chaque fichier : ce qu'il produit, pour qui, et pourquoi
  les choix non évidents.
- Échouer tôt et clairement : `required` et `fail` avec un message qui dit quelle
  clé corriger (ex. `databases.clusters.<nom> absent`).
- Tester : `helm template <release> <chart>/<version> -f <values>` puis
  `scripts/compare-versions.sh`.
