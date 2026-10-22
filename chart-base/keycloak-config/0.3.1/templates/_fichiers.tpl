{{- /* Contenu de la ConfigMap des realms : un fichier JSON par realm (master compris).
       Aussi utilisé pour nommer le Job d'import (hash) : toute modification relance l'import. */}}
{{- define "kc.realmFiles" -}}
{{- if .Values.master.enabled }}
master.json: |
{{ include "kc.masterJson" (dict "root" $) | indent 2 }}
{{- end }}
{{- range $name, $r := .Values.realms }}
{{- if eq $name "master" }}{{ fail "realm master : utiliser la clé master des values" }}{{ end }}
{{ $name }}.json: |
{{ include "kc.realmJson" (dict "root" $ "name" $name "realm" $r) | indent 2 }}
{{- end }}
{{- end -}}
