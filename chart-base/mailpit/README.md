# mailpit (chart maison)

Serveur SMTP de test **central**, partagé par tous les projets (dev, qualif) :
[Mailpit](https://mailpit.axl.dev) capture les e-mails et n'envoie rien vers
l'extérieur. L'interface est protégée par [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/)
(SSO Keycloak, realm `platform`).

```
pods <env>-<projet> ──SMTP 1025──► Service mailpit.mailpit.svc.cluster.local
                                     │
                                   Deployment mailpit ── PVC mailpit-data (1Gi, base SQLite)
                                     │ UI/API 8025 (interne)
navigateur ─► Ingress mailpit ─► oauth2-proxy (4180) ── login ─► Keycloak (realm platform)
                                     └─ rôle mailpit:viewer requis, sinon 403
```

## Deux Applications, un chart

| Application | Wave | Values | Rôle |
|---|---|---|---|
| `mailpit` | 30 | `mailpit.enabled` | Mailpit, PVC, Service. Crée le namespace `mailpit` **avant** `keycloak-config` (35), qui y copie le secret du client (`mailpit-oauth`). |
| `mailpit-auth` | 40 | `oauth2Proxy.enabled` | oauth2-proxy, Service, Ingress ; Job PreSync qui génère le cookie secret (`mailpit-oauth2-cookie`). |

Une seule Application ne suffit pas : en wave 40, le namespace n'existerait pas
quand `keycloak-config` copie le secret ; en wave 30, oauth2-proxy attendrait un
secret créé plus tard (35) et bloquerait les waves suivantes.

## Envoyer depuis un projet

`helm.yaml` du projet :

```yaml
envList:
  - key: SMTP_HOST
    value: {dev: mailpit.mailpit.svc.cluster.local, qualif: mailpit.mailpit.svc.cluster.local}
  - key: SMTP_PORT
    value: "1025"
  - key: SMTP_USER          # tag du mail dans l'UI : <env>-<projet>
    value: {dev: dev-<projet>, qualif: qualif-<projet>}
  - key: SMTP_PASSWORD      # non vérifié (MP_SMTP_AUTH_ACCEPT_ANY)
    value: x
```

Spring Boot : `spring.mail.properties.mail.smtp.auth: true`, sinon le login
n'est pas envoyé et le mail arrive sans tag.

## Accès à l'interface

- `https://mailpit.<env>.check-consulting.net` → connexion Keycloak.
- Droit : rôle `viewer` du client `mailpit` (`gitops/values/common/access.yaml`,
  `access.tools.mailpit`), donné aux groupes. Se reconnecter après un changement.
- Filtrer un projet : `tag:dev-<projet>` dans la recherche.
- Tous les utilisateurs autorisés voient **tous** les e-mails (Mailpit n'a pas de
  notion d'utilisateur) : données de test uniquement.

## Tests e2e (API, dans le cluster)

`http://mailpit.mailpit.svc.cluster.local:8025/api/v1/...` sans authentification
(n'importe quel pod du cluster peut lire les e-mails : pas de NetworkPolicy).

## Values

Voir `values.yaml`. Variables Mailpit : `mailpit.env` (`MP_*`), `MP_DATABASE`,
`MP_SMTP_BIND_ADDR` et `MP_UI_BIND_ADDR` étant posées par le chart.
