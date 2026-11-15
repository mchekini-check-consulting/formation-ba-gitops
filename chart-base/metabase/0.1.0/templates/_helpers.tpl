{{- define "metabase.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "metabase.labels" -}}
{{ include "metabase.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "metabase.selectorLabels" -}}
app.kubernetes.io/name: metabase
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
