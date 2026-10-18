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
