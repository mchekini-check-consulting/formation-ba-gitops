{{- define "cloudbeaver.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cloudbeaver.labels" -}}
{{ include "cloudbeaver.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "cloudbeaver.selectorLabels" -}}
app.kubernetes.io/name: cloudbeaver
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
