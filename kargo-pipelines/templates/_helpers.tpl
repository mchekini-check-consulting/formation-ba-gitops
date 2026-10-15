{{- /* Expression Kargo ${{ ... }} : les accolades sont échappées pour Helm.
       Usage : {{ include "kp.expr" "vars.repoURL" }} -> ${{ vars.repoURL }} */}}
{{- define "kp.expr" -}}
${{ "{{" }} {{ . }} }}
{{- end }}

{{- /* Dépôt ECR d'un composant : <registre>/<dépôt GitHub>/<composant> */}}
{{- define "kp.image" -}}
{{ .root.Values.registry }}/{{ .project }}/{{ .component }}
{{- end }}
