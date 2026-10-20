{{- /*
Sauvegarde logique d'une base (backup.logical, surchargeable par base :
databases.<base>.logical) : CronJob pg_dump -> S3.
  s3://<bucket>/<env>/<namespace>/<cluster>/dumps/<base>/<horodatage>.dump
  schedule      : cron à 5 champs (format Kubernetes)
  retentionDays : dumps plus anciens supprimés à chaque exécution (la version
                  S3 reste récupérable pendant la durée de l'Object Lock)
pg_dump : image PostgreSQL du cluster (même version majeure), rôle de initdb
(Secret <cluster>-app, propriétaire des bases). Envoi : aws-cli, avec le
ServiceAccount <cluster> (rôle IRSA des sauvegardes).
Entrée : dict { ctx (sortie de pg-lib.config), db, logical (config effective) }.
*/}}
{{- define "pg-lib.dumpCronJob" -}}
{{- $ctx := .ctx }}
{{- $l := .logical }}
{{- $name := printf "%s-dump-%s" $ctx.name (.db | replace "_" "-") }}
{{- if gt (len $name) 52 }}
{{- fail (printf "CronJob %s : nom de plus de 52 caractères (cluster ou base trop longs)" $name) }}
{{- end }}
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "1"    # après le Cluster
  labels:
    {{- include "pg-lib.labels" $ctx | nindent 4 }}
spec:
  schedule: {{ $l.schedule | quote }}
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        metadata:
          labels:
            {{- include "pg-lib.labels" $ctx | nindent 12 }}
        spec:
          serviceAccountName: {{ $ctx.name }}
          restartPolicy: Never
          volumes:
            - name: dump
              emptyDir: {}
          initContainers:
            - name: pg-dump
              image: {{ $ctx.cfg.imageName }}
              command: ["pg_dump", "--format=custom", "--file=/dump/db.dump"]
              env:
                - name: PGHOST
                  value: {{ $ctx.name }}-rw
                - name: PGPORT
                  value: "5432"
                - name: PGDATABASE
                  value: {{ .db }}
                - name: PGUSER
                  valueFrom:
                    secretKeyRef:
                      name: {{ $ctx.name }}-app
                      key: username
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: {{ $ctx.name }}-app
                      key: password
              volumeMounts:
                - name: dump
                  mountPath: /dump
          containers:
            - name: upload
              image: {{ $ctx.cfg.awsCliImage }}
              command: ["bash", "-c"]
              args:
                - |
                  set -euo pipefail
                  aws s3 cp /dump/db.dump "s3://$BUCKET/$PREFIX/$(date -u +%Y%m%dT%H%M%SZ).dump"
                  limit=$(date -u -d "-$RETENTION_DAYS days" +%Y%m%dT%H%M%SZ)
                  for key in $(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$PREFIX/" --query 'Contents[].Key' --output text); do
                    [ "$key" = "None" ] && continue
                    if [[ "$(basename "$key" .dump)" < "$limit" ]]; then
                      aws s3 rm "s3://$BUCKET/$key"
                    fi
                  done
              env:
                - name: BUCKET
                  value: {{ $ctx.s3.bucket }}
                - name: PREFIX
                  value: {{ include "pg-lib.s3Prefix" $ctx }}/{{ $ctx.name }}/dumps/{{ .db }}
                - name: RETENTION_DAYS
                  value: {{ $l.retentionDays | quote }}
                - name: AWS_REGION
                  value: {{ $ctx.s3.region }}
              volumeMounts:
                - name: dump
                  mountPath: /dump
{{- end }}
