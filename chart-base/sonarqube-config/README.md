# sonarqube-config

Groupes et permissions globales SonarQube depuis la matrice d'accès
(`values/common/access.yaml`, `tools.sonarqube.roles`). La connexion SAML place
ensuite les utilisateurs dans ces groupes (rôle Keycloak renommé en groupe, voir
[keycloak-config](../keycloak-config/README.md)).

## Fonctionnement

Un seul Job (`templates/job.yaml`), nommé d'après le hash de la configuration :
relancé seulement quand la matrice change. Pour chaque rôle qui porte un `group`
(hors groupes intégrés) :

1. crée le groupe s'il n'existe pas ;
2. aligne ses permissions globales sur `permissions` (ajoute et retire).

Un groupe retiré de la matrice n'est pas supprimé de SonarQube.

## Prérequis

Jeton d'un administrateur, créé une fois à la main (voir `values.yaml`) dans le
Secret `sonarqube-admin-token`. Sans lui, le Job se termine sans rien faire.

## Tester

```bash
cd chart-base
helm template sonarqube-config sonarqube-config/0.1.0 -n sonarqube \
  -f ../gitops/values/common/access.yaml -f ../gitops/values/common/sonarqube-config.yaml
```
