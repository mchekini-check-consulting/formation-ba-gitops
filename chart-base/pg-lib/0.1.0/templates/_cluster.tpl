{{- /*
Cluster CloudNativePG. Entrée : sortie de pg-lib.config.
Réglages fixes repris du chart upstream cluster 0.9.0 (migration sans changement
du spec existant). Sauvegarde physique : plugin Barman Cloud, archiveur des WAL
(PITR), ObjectStore du même nom. Accès S3 : rôle IRSA sur le ServiceAccount
<nom> créé par CNPG (utilisé aussi par les CronJobs de dump).
*/}}
{{- define "pg-lib.cluster" -}}
{{- $c := .cfg }}
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
  annotations:
    {{- include "pg-lib.protect" . | nindent 4 }}
  labels:
    {{- include "pg-lib.labels" . | nindent 4 }}
spec:
  instances: {{ $c.instances }}
  imageName: {{ required "databases.defaults.imageName requis" $c.imageName }}
  imagePullPolicy: IfNotPresent
  postgresUID: 26
  postgresGID: 26
  storage:
    size: {{ $c.storage }}
  affinity:
    topologyKey: topology.kubernetes.io/zone
  primaryUpdateMethod: switchover
  primaryUpdateStrategy: unsupervised
  stopDelay: 1800
  logLevel: info
  enableSuperuserAccess: {{ $c.superuser }}
  enablePDB: {{ $c.enablePDB }}
  monitoring:
    disableDefaultQueries: false
    tls:
      enabled: false
  {{- if or $c.backup.physical.enabled $c.backup.logical.enabled }}
  serviceAccountTemplate:
    metadata:
      annotations:
        eks.amazonaws.com/role-arn: {{ .s3.roleArn }}
  {{- end }}
  {{- if $c.backup.physical.enabled }}
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: {{ .name }}
  {{- end }}
  bootstrap:
    initdb:
      database: {{ $c.initdb.database }}
      owner: {{ $c.initdb.owner }}
{{- end }}
