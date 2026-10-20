{{- /*
Cluster CloudNativePG. Entrée : sortie de pg-lib.config.
Réglages fixes repris du chart upstream cluster 0.9.0 (migration sans changement
du spec existant). Sauvegarde physique : plugin Barman Cloud, archiveur des WAL
(PITR) dans l'archive <archive>, ObjectStore du même nom que le cluster. Accès
S3 : rôle IRSA sur le ServiceAccount <nom> créé par CNPG (utilisé aussi par les
CronJobs de dump).
Restauration (restore.enabled) : bootstrap.recovery depuis l'archive <restoreFrom>,
jusqu'à restore.targetTime (vide = dernier WAL archivé), SANS archivage : la base
restaurée n'écrit dans sa nouvelle archive qu'une fois restore.enabled repassé à
false (procédure : README.md de gitops).
bootstrap n'est lu qu'à la création du Cluster : sur un Cluster existant, le
changer n'a pas d'effet.
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
  {{- if or $c.backup.physical.enabled $c.backup.logical.enabled $c.restore.enabled }}
  serviceAccountTemplate:
    metadata:
      annotations:
        eks.amazonaws.com/role-arn: {{ .s3.roleArn }}
  {{- end }}
  {{- if and $c.backup.physical.enabled (not $c.restore.enabled) }}
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      enabled: true          # valeur par défaut ajoutée par le webhook CNPG : explicite, sinon ArgoCD voit un écart
      isWALArchiver: true
      parameters:
        barmanObjectName: {{ .name }}
        {{- if ne .archive .name }}
        serverName: {{ .archive }}
        {{- end }}
  {{- end }}
  bootstrap:
    {{- if $c.restore.enabled }}
    recovery:
      source: origine
      database: {{ $c.initdb.database }}
      owner: {{ $c.initdb.owner }}
      {{- with $c.restore.targetTime }}
      recoveryTarget:
        targetTime: {{ . | quote }}
      {{- end }}
    {{- else }}
    initdb:
      database: {{ $c.initdb.database }}
      owner: {{ $c.initdb.owner }}
    {{- end }}
  {{- if $c.restore.enabled }}
  externalClusters:
    - name: origine
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: {{ .name }}   # même bucket et préfixe <env>/<namespace>
          serverName: {{ .restoreFrom }}
  {{- end }}
{{- end }}
