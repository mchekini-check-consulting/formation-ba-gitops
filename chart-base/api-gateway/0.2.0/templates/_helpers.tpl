{{- /* Host de la passerelle : api.<env>.<domain> (partagé par tous les projets
       de cet environnement — plusieurs IngressRoute, une par projet, s'y
       agrègent nativement côté Traefik). */}}
{{- define "gw.host" -}}
api.{{ required "env requis (injecté par l'ApplicationSet)" .Values.env }}.{{ .Values.domain }}
{{- end -}}

{{- /* Routes du projet courant, une par application type: backend
       (helm.yaml du projet, source $app) :
       - prefix    : /<projet>/<backend>
       - service   : nom du Service du backend
       - namespace : <env>-<projet> */}}
{{- define "gw.routes" -}}
{{- range .Values.applications }}
{{- if eq .type "backend" }}
- prefix: /{{ $.Values.project }}/{{ .name }}
  service: {{ .name }}
  namespace: {{ $.Values.env }}-{{ $.Values.project }}
{{- end }}
{{- end }}
{{- end -}}

{{- /* Origines CORS du projet courant : applications non type:backend
       (frontends) sur leur host par défaut, plus extraOrigins. */}}
{{- define "gw.origins" -}}
{{- range .Values.applications }}
{{- if ne .type "backend" }}
- https://{{ .name }}.{{ $.Values.project }}.{{ $.Values.env }}.{{ $.Values.domain }}
{{- end }}
{{- end }}
{{- range .Values.extraOrigins }}
- {{ . }}
{{- end }}
{{- end -}}

{{- define "gw.labels" -}}
app.kubernetes.io/name: api-gateway
app.kubernetes.io/instance: {{ .Release.Name }}
env: {{ .Values.env }}
project: {{ .Values.project }}
{{- end -}}
