# cloudbeaver

CloudBeaver CE (administration des bases PostgreSQL dans le navigateur). Écrit
ici faute de chart officiel.

## Utilisé par

Application `cloudbeaver` (namespace `cloudbeaver`), avec
`values/common/cloudbeaver.yaml` et `values/<env>/cloudbeaver.yaml`. Sa base
interne (comptes, équipes, droits) est le Cluster `cloudbeaver-db` (pg-cluster).

## Fichiers (templates/)

| Fichier | Produit |
|---|---|
| `admin-secret-generator.yaml` | hook PreSync : crée le Secret du mot de passe admin s'il n'existe pas |
| `deployment.yaml` | CloudBeaver, configuré au premier démarrage par variables `CB_*` |
| `pvc.yaml` | workspace (connexions, identifiants chiffrés), conservé si l'Application est supprimée |
| `service.yaml`, `ingress.yaml` | exposition |

## Pièges

- Le compte admin (`server.admin`) n'est créé qu'au **premier** démarrage. Si la
  base interne est recréée vide, CloudBeaver reste « configuré » (fichier
  `.cloudbeaver.runtime.conf` du workspace) et ne recrée pas l'admin : renommer ce
  fichier puis redémarrer le pod.
- Une seule instance (`Recreate`) : le workspace est en ReadWriteOnce.
- Les connexions aux bases ne sont pas dans Git : créées dans l'interface.
