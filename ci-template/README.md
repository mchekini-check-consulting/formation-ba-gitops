# ci-template

Briques CI communes aux dépôts métier `formation-ba-*`, sous forme d'actions
composites GitHub, appelées depuis `.github/workflows/` de chaque dépôt :

```yaml
- uses: mchekini-check-consulting/formation-ba-gitops/ci-template/<action>@main
```

Push sur main (`ci.yaml`) :

| Action           | Rôle                                                                        |
|------------------|-----------------------------------------------------------------------------|
| `detect-changes` | liste les dossiers modifiés contenant un Dockerfile + sha court (7 car.)    |
| `build-push`     | construit l'image d'un dossier et la pousse dans ECR (OIDC)                 |
| `update-tag`     | écrit le sha dans `helm.yaml` (`tag.dev`) et pousse le commit -> ArgoCD dev |

Pull request (`pr.yaml`) :

| Action             | Rôle                                                                     |
|--------------------|--------------------------------------------------------------------------|
| `setup`            | détecte la stack (node / maven / python), installe runtime + dépendances |
| `lint`             | `make lint`                                                              |
| `gitleaks`         | secrets dans les commits de la PR                                        |
| `unit-test`        | `make test-unit` (tests + rapport de couverture)                         |
| `sonarqube`        | analyse du composant + attente du quality gate (même job que unit-test)  |
| `integration-test` | `make test-integration`                                                  |

Contrat de chaque composant (dossier avec Dockerfile) :
- `Makefile` avec les cibles `lint`, `test-unit`, `test-integration` : la CI ne connaît
  pas les commandes de la stack, elle appelle seulement ces cibles (utilisables en local).
- `sonar-project.properties` : sources, tests et chemin du rapport de couverture produit
  par `test-unit`. Projet Sonar : `<dépôt>-<composant>`.

Le dépôt appelant fait lui-même le `actions/checkout` (avec `fetch-depth: 0`
pour `detect-changes`, `gitleaks` et `sonarqube`) et porte les `permissions` des jobs.

Secret d'organisation requis pour `sonarqube` : `SONAR_TOKEN` (Global Analysis Token,
permission « Create Projects »). L'URL du serveur est la valeur par défaut de l'input
`host-url` (https://sonarqube-dev.check-consulting.net).

Dépôt privé : autoriser l'accès dans
Settings > Actions > General > Access > « Accessible from repositories in the organization ».
