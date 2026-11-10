{{- /* Noms fixes (pas le nom de release) : les deux Applications (mailpit,
       mailpit-auth) partagent le namespace et se référencent par ces noms. */}}

{{- define "mailpit.labels" -}}
app.kubernetes.io/part-of: mailpit
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ .root.Chart.Name }}-{{ .root.Chart.Version }}
{{ include "mailpit.selectorLabels" . }}
{{- end -}}

{{/* Labels de sélection (immuables sur un Deployment). Entrée : dict "root" $ "component" <nom> */}}
{{- define "mailpit.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}
