# keycloak-config

Configuration Keycloak « as code » : realms, clients (un par outil), rôles,
groupes et utilisateurs, générés depuis les values et appliqués par
[keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli).

## Utilisé par

Application `keycloak-config` (namespace `keycloak`, wave 35), avec
`values/common/access.yaml` (matrice d'accès), `values/common/keycloak-config.yaml`
et `values/<env>/keycloak-config.yaml` (utilisateurs, domaine).

## Ce qui se passe à chaque synchronisation

| Ordre | Objet | Fichier | Rôle |
|---|---|---|---|
| PreSync, wave -1/0 | Job `*-secrets` | `secret-generator.yaml` | crée les Secrets absents (mot de passe initial, secrets des clients) |
| PreSync, wave 1 | Job `*-cli-client` | `cli-client.yaml` | garantit le client de service de keycloak-config-cli (realm master) |
| Sync | Issuer + Certificates | `signing-keys.yaml` | clés de signature fixées des realms (`signingKey: true`) |
| Sync | ConfigMap `*-realms` | `configmap.yaml` | un fichier JSON par realm |
| Sync | Job `keycloak-config-<hash>` | `job.yaml` | import ; nouveau Job seulement si les realms ou la version du chart changent |
| PostSync | Job `*-idp-cert` | `idp-certificate.yaml` | copie le certificat de l'IdP vers les outils SAML (SonarQube) |
| PostSync | Job `*-client-secrets` | `client-secret-copy.yaml` | copie le secret des clients OIDC confidentiels vers leur outil (`clientSecretCopy`, ex. Grafana) — depuis 0.3.2 |

## Construction des realms (templates/_*.tpl)

| Fichier | Contenu |
|---|---|
| `_fichiers.tpl` | contenu de la ConfigMap : `master.json` + un `<realm>.json` par realm |
| `_realm.tpl` | un realm : réglages, clients (`kc.client`), groupes et rôles (`kc.realmGroups`), utilisateurs (`kc.user`) |
| `_master.tpl` | realm master : client de service, compte de démarrage, administrateurs |
| `_mfa.tpl` | flux de connexion `browser-mfa` (mot de passe puis OTP) |
| `_acces.tpl` | rôles et groupes depuis la matrice d'accès, avec vérification des références |
| `_listes.tpl` | clients confidentiels, realms à clé fixée, certificats et secrets de clients à copier |
| `_commun.tpl` | noms, labels, annotations de hooks |

Chaque partie est écrite en YAML puis convertie en JSON (`toPrettyJson`, clés
triées) : pour savoir ce qui part dans Keycloak, lire le YAML du template.

## Faire évoluer

- Ajouter un utilisateur, un groupe, un client : values uniquement
  (`values/<env>/keycloak-config.yaml`, `values/common/access.yaml`).
- Le tag de l'image (`image.tag`) suit la version de Keycloak : à monter avec le
  chart `keycloakx`.
- Une montée de version du chart relance l'import une fois (sans effet si rien
  n'a changé).

## Tester

```bash
cd chart-base
helm template keycloak-config keycloak-config/0.3.2 -n keycloak \
  -f ../gitops/values/common/access.yaml \
  -f ../gitops/values/common/keycloak-config.yaml \
  -f ../gitops/values/dev/keycloak-config.yaml
```

Une faute de frappe (groupe, rôle ou client inconnu) fait échouer le rendu avec
un message qui nomme la clé à corriger.
