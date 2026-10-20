{{- /*
Base logique (ressource Database CNPG), propriétaire = rôle de initdb.
Une base existante (créée par initdb) est reprise telle quelle.
retain : retirer la base des values ne fait pas de DROP DATABASE.
Entrée : dict { ctx (sortie de pg-lib.config), db (nom de la base) }.
*/}}
{{- define "pg-lib.database" -}}
{{- $ctx := .ctx }}
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: {{ $ctx.name }}-{{ .db | replace "_" "-" }}
  namespace: {{ $ctx.namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "1"    # après le Cluster
    {{- include "pg-lib.protect" . | nindent 4 }}
  labels:
    {{- include "pg-lib.labels" $ctx | nindent 4 }}
spec:
  name: {{ .db }}
  owner: {{ $ctx.cfg.initdb.owner }}
  cluster:
    name: {{ $ctx.name }}
  ensure: present
  databaseReclaimPolicy: retain
{{- end }}
