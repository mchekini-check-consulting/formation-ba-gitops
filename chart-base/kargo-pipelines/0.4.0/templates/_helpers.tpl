{{- /* Expression Kargo ${{ ... }} : les accolades sont échappées pour Helm.
       Usage : {{ include "kp.expr" "vars.repoURL" }} -> ${{ vars.repoURL }} */}}
{{- define "kp.expr" -}}
${{ "{{" }} {{ . }} }}
{{- end }}

{{- /* Dépôt ECR d'un composant du projet courant : <registre>/<dépôt>/<composant> */}}
{{- define "kp.image" -}}
{{ .root.Values.registry }}/{{ .root.Values.project }}/{{ .component }}
{{- end }}

{{- /* Droits SSO par Project, depuis access.tools.kargo.roles (liste YAML) :
         project: kargo-<admin|promoter|viewer>  -> ServiceAccount sso-<admin|promoter|viewer>
                                                    lié au Role créé par Kargo
         projectRules: [...]                     -> Role + ServiceAccount sso-role-<rôle>
       claims : rôles Keycloak qui donnent ce droit. */}}
{{- define "kp.ssoBindings" -}}
{{- $roles := dig "tools" "kargo" "roles" dict (.Values.access | default dict) }}
{{- $byRole := dict }}
{{- range $role, $r := $roles }}
{{- if $r.projectRules }}
- name: sso-role-{{ $role }}
  role: sso-role-{{ $role }}
  claims: [{{ $role }}]
  rules:
    {{- toYaml $r.projectRules | nindent 4 }}
{{- else if $r.project }}
{{- if not (has $r.project (list "kargo-admin" "kargo-promoter" "kargo-viewer")) }}
{{- fail (printf "access.tools.kargo.roles.%s.project : kargo-admin, kargo-promoter ou kargo-viewer (reçu %s)" $role $r.project) }}
{{- end }}
{{- $_ := set $byRole $r.project (append (get $byRole $r.project | default list) $role) }}
{{- end }}
{{- end }}
{{- range $projectRole, $claims := $byRole }}
- name: sso-{{ trimPrefix "kargo-" $projectRole }}
  role: {{ $projectRole }}
  claims: {{ toJson $claims }}
{{- end }}
{{- end -}}
