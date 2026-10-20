{{- /*
Sauvegarde physique (backup.physical) : ObjectStore + ScheduledBackup.
  s3://<bucket>/<env>/<namespace>/<archive>/   base complète + WAL archivés en continu
                                               (<archive> : <cluster> ou <cluster>-g<N>)
  retention : fenêtre de restauration (PITR), appliquée par le plugin
  schedule  : cron à 6 champs (secondes en tête), format CNPG
Entrée : sortie de pg-lib.config.
*/}}
{{- define "pg-lib.objectStore" -}}
{{- $p := .cfg.backup.physical }}
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "-1"   # avant le Cluster qui le référence
  labels:
    {{- include "pg-lib.labels" . | nindent 4 }}
spec:
  retentionPolicy: {{ $p.retention | quote }}
  configuration:
    destinationPath: s3://{{ .s3.bucket }}/{{ include "pg-lib.s3Prefix" . }}
    s3Credentials:
      inheritFromIAMRole: true
    wal:
      compression: gzip
    data:
      compression: gzip
{{- end }}

{{- define "pg-lib.scheduledBackup" -}}
{{- $p := .cfg.backup.physical }}
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "1"    # après le Cluster
  labels:
    {{- include "pg-lib.labels" . | nindent 4 }}
spec:
  schedule: {{ $p.schedule | quote }}
  immediate: true            # première sauvegarde dès la création
  backupOwnerReference: self
  cluster:
    name: {{ .name }}
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
{{- end }}
