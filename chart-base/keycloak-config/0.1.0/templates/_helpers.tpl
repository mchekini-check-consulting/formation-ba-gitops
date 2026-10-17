{{- define "kc.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kc.labels" -}}
app.kubernetes.io/name: keycloak-config
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- /* Clients OIDC confidentiels (public: false), sous forme de liste YAML :
       realm, client, secret (nom du Secret K8s), env (variable lue par l'import). */}}
{{- define "kc.confidentialClients" -}}
{{- range $realm, $r := .Values.realms }}
{{- range $cid, $c := $r.clients }}
{{- if and (eq ($c.protocol | default "openid-connect") "openid-connect") (not $c.public) }}
- realm: {{ $realm }}
  client: {{ $cid }}
  secret: keycloak-client-{{ $realm }}-{{ $cid }}
  env: CLIENT_SECRET_{{ printf "%s_%s" $realm $cid | upper | replace "-" "_" | replace "." "_" }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- /* Realm au format JSON de keycloak-config-cli (RealmRepresentation).
       Entrée : dict root, name, realm. Les références (groupe -> client/rôle,
       utilisateur -> groupe) sont vérifiées ici : une faute de frappe échoue au rendu. */}}
{{- define "kc.realmJson" -}}
{{- $root := .root }}
{{- $name := .name }}
{{- $r := .realm | default dict }}
{{- $realm := merge (dict "realm" $name "enabled" true) (deepCopy ($r.settings | default dict)) (deepCopy $root.Values.realmDefaults) }}
{{- with $r.displayName }}{{ $_ := set $realm "displayName" . }}{{ end }}

{{- /* Clients et leurs rôles */}}
{{- $clients := list }}
{{- $clientRoles := dict }}
{{- range $cid, $c := $r.clients }}
{{- $protocol := $c.protocol | default "openid-connect" }}
{{- $client := dict "clientId" $cid "name" ($c.name | default $cid) "enabled" true "protocol" $protocol }}
{{- $base := "" }}
{{- if $c.host }}
{{- $base = printf "https://%s.%s" $c.host (required "baseDomain requis (client avec host)" $root.Values.baseDomain) }}
{{- $_ := set $client "rootUrl" $base }}
{{- $_ := set $client "baseUrl" "/" }}
{{- end }}
{{- $redirects := list }}
{{- range $c.redirectPaths }}{{ $redirects = append $redirects (printf "%s%s" $base .) }}{{ end }}
{{- range $c.extraRedirectUris }}{{ $redirects = append $redirects . }}{{ end }}
{{- if $redirects }}{{ $_ := set $client "redirectUris" $redirects }}{{ end }}
{{- $attributes := deepCopy ($c.attributes | default dict) }}
{{- $mappers := list }}
{{- if eq $protocol "openid-connect" }}
{{- $_ := set $client "publicClient" (default false $c.public) }}
{{- $_ := set $client "standardFlowEnabled" true }}
{{- $_ := set $client "directAccessGrantsEnabled" false }}
{{- $_ := set $client "webOrigins" (list "+") }}
{{- $_ := set $attributes "post.logout.redirect.uris" "+" }}
{{- if $c.public }}
{{- $_ := set $attributes "pkce.code.challenge.method" "S256" }}
{{- else }}
{{- $_ := set $client "clientAuthenticatorType" "client-secret" }}
{{- $_ := set $client "secret" (printf "$(env:CLIENT_SECRET_%s)" (printf "%s_%s" $name $cid | upper | replace "-" "_" | replace "." "_")) }}
{{- end }}
{{- /* Rôles de CE client dans un claim plat (ex. roles: [admin]) */}}
{{- $mappers = append $mappers (dict
      "name" "client-roles"
      "protocol" "openid-connect"
      "protocolMapper" "oidc-usermodel-client-role-mapper"
      "consentRequired" false
      "config" (dict
        "usermodel.clientRoleMapping.clientId" $cid
        "claim.name" ($c.rolesClaim | default "roles")
        "multivalued" "true"
        "jsonType.label" "String"
        "id.token.claim" "true"
        "access.token.claim" "true"
        "userinfo.token.claim" "true"
        "introspection.token.claim" "true")) }}
{{- end }}
{{- range $c.protocolMappers }}{{ $mappers = append $mappers . }}{{ end }}
{{- if $attributes }}{{ $_ := set $client "attributes" $attributes }}{{ end }}
{{- if $mappers }}{{ $_ := set $client "protocolMappers" $mappers }}{{ end }}
{{- $clients = append $clients $client }}
{{- with $c.roles }}
{{- $roles := list }}
{{- range . }}{{ $roles = append $roles (dict "name" .) }}{{ end }}
{{- $_ := set $clientRoles $cid $roles }}
{{- end }}
{{- end }}
{{- if $clients }}{{ $_ := set $realm "clients" $clients }}{{ end }}
{{- if $clientRoles }}{{ $_ := set $realm "roles" (dict "client" $clientRoles) }}{{ end }}

{{- /* Groupes : composition de rôles clients */}}
{{- $groups := list }}
{{- range $gname, $g := $r.groups }}
{{- $group := dict "name" $gname }}
{{- range $cid, $croles := ($g.clientRoles | default dict) }}
{{- if not (hasKey ($r.clients | default dict) $cid) }}
{{- fail (printf "realm %s, groupe %s : client %s inconnu" $name $gname $cid) }}
{{- end }}
{{- range $croles }}
{{- if not (has . (index $r.clients $cid).roles) }}
{{- fail (printf "realm %s, groupe %s : rôle %s absent du client %s" $name $gname . $cid) }}
{{- end }}
{{- end }}
{{- end }}
{{- with $g.clientRoles }}{{ $_ := set $group "clientRoles" . }}{{ end }}
{{- $groups = append $groups $group }}
{{- end }}
{{- if $groups }}{{ $_ := set $realm "groups" $groups }}{{ end }}

{{- /* Utilisateurs : mot de passe initial temporaire (userLabel "initial" : posé
       à la création seulement, jamais réappliqué) */}}
{{- $users := list }}
{{- range $uname, $u := $r.users }}
{{- range ($u.groups | default list) }}
{{- if not (hasKey ($r.groups | default dict) .) }}
{{- fail (printf "realm %s, utilisateur %s : groupe %s inconnu" $name $uname .) }}
{{- end }}
{{- end }}
{{- $user := dict
      "username" $uname
      "enabled" (ternary $u.enabled true (hasKey $u "enabled"))
      "emailVerified" true
      "groups" ($u.groups | default list)
      "credentials" (list (dict
        "type" "password"
        "userLabel" "initial"
        "temporary" true
        "value" "$(env:USER_INITIAL_PASSWORD)")) }}
{{- with $u.email }}{{ $_ := set $user "email" . }}{{ end }}
{{- with $u.firstName }}{{ $_ := set $user "firstName" . }}{{ end }}
{{- with $u.lastName }}{{ $_ := set $user "lastName" . }}{{ end }}
{{- $users = append $users $user }}
{{- end }}
{{- if $users }}{{ $_ := set $realm "users" $users }}{{ end }}
{{- toPrettyJson $realm }}
{{- end -}}

{{- /* Contenu de la ConfigMap : un fichier JSON par realm */}}
{{- define "kc.realmFiles" -}}
{{- range $name, $r := .Values.realms }}
{{ $name }}.json: |
{{ include "kc.realmJson" (dict "root" $ "name" $name "realm" $r) | indent 2 }}
{{- end }}
{{- end -}}
