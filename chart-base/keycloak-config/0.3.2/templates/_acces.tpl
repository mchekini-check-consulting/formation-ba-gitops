{{- /* Rôles et groupes d'un realm, avec vérification des références.

       Deux sources possibles :
       - le realm de la matrice d'accès (access.realm, gitops/values/common/access.yaml) :
           rôles   = access.tools.<client>.roles
           groupes = access.groups
       - tout autre realm : roles et groups déclarés dans le realm lui-même.

       Entrée : dict "root" $ "name" <realm> "realm" <values du realm>
       Sortie (YAML, à relire avec fromYaml) :
         roles:   {<client>: [rôles triés]}
         groups:  {<groupe>: {clientRoles: {<client>: [rôles]}, mfa: bool}}
         catalog: {<client>: {<rôle>: définition de la matrice}}   (realm de la matrice seulement)
       Un client, un groupe ou un rôle inconnu fait échouer le rendu. */}}
{{- define "kc.realmAccess" -}}
{{- $name := .name }}
{{- $r := .realm | default dict }}
{{- $access := .root.Values.access | default dict }}
{{- $roles := dict }}
{{- $groups := dict }}
{{- $catalog := dict }}

{{- if eq ($access.realm | default "") $name }}
  {{- /* Realm de la matrice d'accès */}}
  {{- range $cid, $t := ($access.tools | default dict) }}
    {{- if not (hasKey ($r.clients | default dict) $cid) }}
      {{- fail (printf "access.tools.%s : pas de client %s dans realms.%s.clients" $cid $cid $name) }}
    {{- end }}
    {{- $_ := set $roles $cid (keys ($t.roles | default dict) | sortAlpha) }}
    {{- $_ := set $catalog $cid ($t.roles | default dict) }}
  {{- end }}
  {{- range $gname, $g := ($access.groups | default dict) }}
    {{- $_ := set $groups $gname (dict "clientRoles" ($g.roles | default dict) "mfa" ($g.mfa | default false)) }}
  {{- end }}
{{- else }}
  {{- /* Realm décrit directement */}}
  {{- range $cid, $c := ($r.clients | default dict) }}
    {{- with $c.roles }}{{ $_ := set $roles $cid . }}{{ end }}
  {{- end }}
  {{- range $gname, $g := ($r.groups | default dict) }}
    {{- $_ := set $groups $gname (dict "clientRoles" ($g.clientRoles | default dict) "mfa" ($g.mfa | default false)) }}
  {{- end }}
{{- end }}

{{- /* Chaque groupe ne référence que des clients et des rôles existants */}}
{{- range $gname, $g := $groups }}
  {{- range $cid, $croles := $g.clientRoles }}
    {{- if not (hasKey $roles $cid) }}
      {{- fail (printf "realm %s, groupe %s : client %s inconnu ou sans rôles" $name $gname $cid) }}
    {{- end }}
    {{- range $croles }}
      {{- if not (has . (index $roles $cid)) }}
        {{- fail (printf "realm %s, groupe %s : rôle %s absent du client %s" $name $gname . $cid) }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- toYaml (dict "roles" $roles "groups" $groups "catalog" $catalog) }}
{{- end -}}
