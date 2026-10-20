{{/*
Valeur pour l'environnement courant : map { dev: x, qualif: y } ou valeur unique.
Entrée : dict "value" <valeur> "env" <env>
*/}}
{{- define "gba.byEnv" -}}
{{- if kindIs "map" .value }}{{ get .value .env }}{{ else }}{{ .value }}{{ end -}}
{{- end -}}

{{/* Labels communs. Entrée : dict "app" <app> "root" $ */}}
{{- define "gba.labels" -}}
{{ include "gba.selectorLabels" . }}
app.kubernetes.io/part-of: {{ .root.Values.project }}
env: {{ .root.Values.env }}
tier: {{ .app.type }}
{{- end -}}

{{/* Labels de sélection (immuables sur un Deployment) */}}
{{- define "gba.selectorLabels" -}}
app.kubernetes.io/name: {{ .app.name }}
{{- end -}}

{{/* Secret TLS du projet (wildcard *.<project>.<env>.<domain>). Entrée : $ */}}
{{- define "gba.tlsSecret" -}}
{{ .Values.project }}-tls
{{- end -}}


{{/* Cluster PostgreSQL du namespace (un par projet et environnement) */}}
{{- define "gba.dbCluster" -}}
app-db
{{- end -}}

{{/* Nom de la base d'une application, vide si pas de base. Entrée : <app> */}}
{{- define "gba.dbName" -}}
{{- if kindIs "map" .database }}
{{- required (printf "%s : database.name requis (ou database: true)" .name) .database.name }}
{{- else if .database }}
{{- .name | replace "-" "_" }}
{{- end }}
{{- end -}}

{{/* Variables de connexion à la base. Les URL réutilisent les variables
     précédentes ($(VAR) : syntaxe Kubernetes). Entrée : dict "db" <base> */}}
{{- define "gba.dbEnv" -}}
- name: PGHOST
  value: {{ include "gba.dbCluster" . }}-rw
- name: PGPORT
  value: "5432"
- name: PGDATABASE
  value: {{ .db }}
- name: PGUSER
  valueFrom:
    secretKeyRef:
      name: {{ include "gba.dbCluster" . }}-app
      key: username
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "gba.dbCluster" . }}-app
      key: password
# Node.js (Prisma, Sequelize, Knex...), Django (dj-database-url)
- name: DATABASE_URL
  value: postgresql://$(PGUSER):$(PGPASSWORD)@$(PGHOST):$(PGPORT)/$(PGDATABASE)
# Spring Boot
- name: SPRING_DATASOURCE_URL
  value: jdbc:postgresql://$(PGHOST):$(PGPORT)/$(PGDATABASE)
- name: SPRING_DATASOURCE_USERNAME
  value: $(PGUSER)
- name: SPRING_DATASOURCE_PASSWORD
  value: $(PGPASSWORD)
{{- end -}}
