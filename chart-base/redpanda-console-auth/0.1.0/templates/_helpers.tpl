{{- define "redpanda-console-auth.labels" -}}
app.kubernetes.io/part-of: redpanda-console
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ .root.Chart.Name }}-{{ .root.Chart.Version }}
{{ include "redpanda-console-auth.selectorLabels" . }}
{{- end -}}

{{/* Entrée : dict "root" $ "component" <nom> */}}
{{- define "redpanda-console-auth.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}
