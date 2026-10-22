{{- /* Fichier JSON d'un realm, au format de keycloak-config-cli (RealmRepresentation).

       Construit en 4 parties, chacune décrite en YAML plus bas :
         1. réglages : realmDefaults < settings du realm < nom du realm
         2. clients et leurs rôles      (kc.client)
         3. groupes, rôles, flux MFA    (kc.realmGroups)
         4. utilisateurs                (kc.user)
       Entrée : dict "root" $ "name" <realm> "realm" <values du realm>. */}}
{{- define "kc.realmJson" -}}
{{- $root := .root }}
{{- $name := .name }}
{{- $r := .realm | default dict }}
{{- $acc := include "kc.realmAccess" . | fromYaml }}

{{- /* 1. Réglages (merge : le premier argument l'emporte) */}}
{{- $realm := merge (dict "realm" $name "enabled" true) (deepCopy ($r.settings | default dict)) (deepCopy $root.Values.realmDefaults) }}
{{- with $r.displayName }}{{ $_ := set $realm "displayName" . }}{{ end }}

{{- /* 2. Clients ; settings du client l'emportent sur les valeurs générées */}}
{{- $clients := list }}
{{- $clientRoles := dict }}
{{- range $cid, $c := $r.clients }}
  {{- $generated := include "kc.client" (dict "root" $root "realm" $name "id" $cid "client" $c "catalog" (index $acc.catalog $cid | default dict)) | fromYaml }}
  {{- $clients = append $clients (merge (deepCopy ($c.settings | default dict)) $generated) }}
  {{- with (index $acc.roles $cid) }}
    {{- $roles := list }}
    {{- range . }}{{ $roles = append $roles (dict "name" .) }}{{ end }}
    {{- $_ := set $clientRoles $cid $roles }}
  {{- end }}
{{- end }}
{{- if $clients }}{{ $_ := set $realm "clients" $clients }}{{ end }}

{{- /* 3. Groupes, rôles et flux de connexion (remplacent les mêmes clés des settings) */}}
{{- range $key, $value := include "kc.realmGroups" (dict "groups" $acc.groups "clientRoles" $clientRoles) | fromYaml }}
  {{- $_ := set $realm $key $value }}
{{- end }}
{{- if $realm.browserFlow | eq "browser-mfa" }}
  {{- $realm = merge $realm (include "kc.mfaFlows" (dict "role" "mfa-required") | fromYaml) }}
{{- end }}

{{- /* 4. Utilisateurs (les groupes référencés doivent exister) */}}
{{- $users := list }}
{{- range $uname, $u := $r.users }}
  {{- range ($u.groups | default list) }}
    {{- if not (hasKey $acc.groups .) }}
      {{- fail (printf "realm %s, utilisateur %s : groupe %s inconnu" $name $uname .) }}
    {{- end }}
  {{- end }}
  {{- $users = append $users (include "kc.user" (dict "username" $uname "user" $u "extra" (dict "groups" ($u.groups | default list))) | fromYaml) }}
{{- end }}
{{- if $users }}{{ $_ := set $realm "users" $users }}{{ end }}
{{- toPrettyJson $realm }}
{{- end -}}

{{- /* Un client (ClientRepresentation), sans ses settings.
       Entrée : dict "root" "realm" "id" "client" "catalog" (rôles de la matrice
       d'accès pour ce client, pour les noms de groupe SAML). */}}
{{- define "kc.client" -}}
{{- $c := .client }}
{{- $oidc := eq ($c.protocol | default "openid-connect") "openid-connect" }}
{{- $base := "" }}
{{- if $c.host }}
  {{- $base = printf "https://%s.%s" $c.host (required "baseDomain requis (client avec host)" .root.Values.baseDomain) }}
{{- end }}
{{- $redirects := list }}
{{- range $c.redirectPaths }}{{ $redirects = append $redirects (printf "%s%s" $base .) }}{{ end }}
{{- range $c.extraRedirectUris }}{{ $redirects = append $redirects . }}{{ end }}
{{- $attributes := deepCopy ($c.attributes | default dict) }}
{{- if $oidc }}
  {{- $_ := set $attributes "post.logout.redirect.uris" "+" }}
  {{- if $c.public }}{{ $_ := set $attributes "pkce.code.challenge.method" "S256" }}{{ end }}
{{- end }}
{{- $samlGroups := and (not $oidc) (eq $c.protocol "saml") $c.samlGroupsAttribute }}
clientId: {{ .id | toJson }}
name: {{ $c.name | default .id | toJson }}
enabled: true
protocol: {{ $c.protocol | default "openid-connect" | toJson }}
{{- if $c.host }}
rootUrl: {{ $base | toJson }}
baseUrl: /
{{- end }}
{{- with $redirects }}
redirectUris: {{ toJson . }}
{{- end }}
{{- if $oidc }}
publicClient: {{ default false $c.public }}
standardFlowEnabled: true
directAccessGrantsEnabled: false
webOrigins: ["+"]
{{- if not $c.public }}
clientAuthenticatorType: client-secret
secret: "$(env:{{ include "kc.clientSecretEnv" (dict "realm" .realm "client" .id) }})"
{{- end }}
{{- end }}
{{- with $attributes }}
attributes: {{ toJson . }}
{{- end }}
{{- if or $oidc $samlGroups $c.protocolMappers }}
protocolMappers:
  {{- if $oidc }}
  # Rôles de CE client dans un claim plat (ex. roles: [admin])
  - name: client-roles
    protocol: openid-connect
    protocolMapper: oidc-usermodel-client-role-mapper
    consentRequired: false
    config:
      usermodel.clientRoleMapping.clientId: {{ .id | toJson }}
      claim.name: {{ $c.rolesClaim | default "roles" | toJson }}
      multivalued: "true"
      jsonType.label: String
      id.token.claim: "true"
      access.token.claim: "true"
      userinfo.token.claim: "true"
      introspection.token.claim: "true"
  {{- end }}
  {{- if $samlGroups }}
  # SAML : rôles dans un seul attribut multi-valeurs...
  - name: groups
    protocol: saml
    protocolMapper: saml-role-list-mapper
    config:
      attribute.name: {{ $c.samlGroupsAttribute | toJson }}
      attribute.nameformat: Basic
      single: "true"
  # ... chaque rôle renommé en groupe de l'outil (group de la matrice d'accès)
  {{- range $role, $def := .catalog }}
  {{- with ($def | default dict).group }}
  - name: role-{{ $role }}
    protocol: saml
    protocolMapper: saml-role-name-mapper
    config:
      role: {{ printf "%s.%s" $.id $role | toJson }}
      new.role.name: {{ . | toJson }}
  {{- end }}
  {{- end }}
  {{- end }}
  {{- with $c.protocolMappers }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end -}}

{{- /* Groupes (composition de rôles clients), rôles et flux de connexion.
       Un groupe mfa: true reçoit le rôle de realm mfa-required, qui déclenche l'OTP
       du flux browser-mfa ; sans aucun groupe mfa, flux standard "browser".
       Entrée : dict "groups" (sortie de kc.realmAccess) "clientRoles" {<client>: [{name}]} */}}
{{- define "kc.realmGroups" -}}
{{- $mfa := false }}
{{- range .groups }}{{ if .mfa }}{{ $mfa = true }}{{ end }}{{ end }}
{{- with .groups }}
groups:
  {{- range $gname, $g := . }}
  - name: {{ $gname | toJson }}
    {{- with $g.clientRoles }}
    clientRoles: {{ toJson . }}
    {{- end }}
    {{- if $g.mfa }}
    realmRoles: [mfa-required]
    {{- end }}
  {{- end }}
{{- end }}
{{- if or .clientRoles $mfa }}
roles:
  {{- with .clientRoles }}
  client: {{ toJson . }}
  {{- end }}
  {{- if $mfa }}
  realm:
    - name: mfa-required
      description: "Code OTP exigé à la connexion (groupes mfa: true)"
  {{- end }}
{{- end }}
browserFlow: {{ ternary "browser-mfa" "browser" $mfa }}
{{- end -}}

{{- /* Utilisateur humain, avec un mot de passe initial temporaire (userLabel "initial" :
       posé à la création seulement, jamais réappliqué ensuite).
       Entrée : dict "username" "user" (values) "extra" (clés en plus : groups, realmRoles). */}}
{{- define "kc.user" -}}
{{- $u := .user | default dict }}
{{- $user := include "kc.userBase" (dict "username" .username "user" $u) | fromYaml }}
{{- toYaml (merge (deepCopy (.extra | default dict)) $user) }}
{{- end -}}

{{- define "kc.userBase" -}}
{{- $u := .user }}
username: {{ .username | toJson }}
enabled: {{ ternary $u.enabled true (hasKey $u "enabled") }}
emailVerified: true
{{- with $u.email }}
email: {{ . | toJson }}
{{- end }}
{{- with $u.firstName }}
firstName: {{ . | toJson }}
{{- end }}
{{- with $u.lastName }}
lastName: {{ . | toJson }}
{{- end }}
credentials:
  - type: password
    userLabel: initial
    temporary: true
    value: "$(env:USER_INITIAL_PASSWORD)"
{{- end -}}
