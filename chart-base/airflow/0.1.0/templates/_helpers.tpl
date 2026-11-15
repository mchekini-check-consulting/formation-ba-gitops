{{- define "airflow.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "airflow.labels" -}}
{{ include "airflow.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "airflow.selectorLabels" -}}
app.kubernetes.io/name: airflow
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
