{{- /* Host de la passerelle : api.<env>.<domain> */}}
{{- define "gw.host" -}}
api.{{ required "env requis (injecté par l'Application)" .Values.env }}.{{ .Values.domain }}
{{- end -}}

{{- /* Routes, une par backend déclaré dans projects[].api (liste YAML) :
       - prefix    : /<projet>/<backend>
       - service   : nom du Service du backend
       - namespace : <env>-<projet> */}}
{{- define "gw.routes" -}}
{{- range $p := .Values.projects }}
{{- range $app := ($p.api | default list) }}
{{- if not (has $app $p.components) }}
{{- fail (printf "business.projects %s : api.%s absent de components" $p.name $app) }}
{{- end }}
- prefix: /{{ $p.name }}/{{ $app }}
  service: {{ $app }}
  namespace: {{ $.Values.env }}-{{ $p.name }}
{{- end }}
{{- end }}
{{- end -}}

{{- /* Origines CORS : composants hors api (frontends) sur leur host par défaut,
       plus extraOrigins (liste YAML). */}}
{{- define "gw.origins" -}}
{{- range $p := .Values.projects }}
{{- range $c := $p.components }}
{{- if not (has $c ($p.api | default list)) }}
- https://{{ $c }}.{{ $p.name }}.{{ $.Values.env }}.{{ $.Values.domain }}
{{- end }}
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
{{- end -}}
