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

{{- /* Realms avec clé de signature fixée (signingKey: true), liste YAML :
       realm, secret (Secret cert-manager tls.key / tls.crt). */}}
{{- define "kc.signingRealms" -}}
{{- range $realm, $r := .Values.realms }}
{{- if $r.signingKey }}
- realm: {{ $realm }}
  secret: keycloak-realm-{{ $realm }}-signing
{{- end }}
{{- end }}
{{- end -}}

{{- /* Clients avec idpCertificateSecret, liste YAML : Secret source (clé du realm)
       et Secret cible (namespace, nom) qui reçoit le certificat. */}}
{{- define "kc.idpCertificateSecrets" -}}
{{- range $realm, $r := .Values.realms }}
{{- range $cid, $c := $r.clients }}
{{- with $c.idpCertificateSecret }}
{{- if not $r.signingKey }}
{{- fail (printf "realm %s, client %s : idpCertificateSecret exige realms.%s.signingKey: true" $realm $cid $realm) }}
{{- end }}
- realm: {{ $realm }}
  source: keycloak-realm-{{ $realm }}-signing
  namespace: {{ required (printf "realm %s, client %s : idpCertificateSecret.namespace requis" $realm $cid) .namespace }}
  name: {{ required (printf "realm %s, client %s : idpCertificateSecret.name requis" $realm $cid) .name }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- /* Rôles et groupes d'un realm. Realm de la matrice d'accès (access.realm) :
       rôles = access.tools.<client>.roles, groupes = access.groups. Sinon : roles
       et groups déclarés dans le realm. Sortie YAML :
         roles:  {<client>: [rôles]}
         groups: {<groupe>: {clientRoles: {<client>: [rôles]}, mfa: bool}}
         catalog: {<client>: {<rôle>: {définition de la matrice}}} */}}
{{- define "kc.realmAccess" -}}
{{- $root := .root }}
{{- $name := .name }}
{{- $r := .realm | default dict }}
{{- $access := $root.Values.access | default dict }}
{{- $roles := dict }}
{{- $groups := dict }}
{{- $catalog := dict }}
{{- if eq ($access.realm | default "") $name }}
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
{{- range $cid, $c := ($r.clients | default dict) }}
{{- with $c.roles }}{{ $_ := set $roles $cid . }}{{ end }}
{{- end }}
{{- range $gname, $g := ($r.groups | default dict) }}
{{- $_ := set $groups $gname (dict "clientRoles" ($g.clientRoles | default dict) "mfa" ($g.mfa | default false)) }}
{{- end }}
{{- end }}
{{- /* Références groupe -> client / rôle */}}
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

{{- /* Flux de connexion "browser-mfa" : mot de passe puis code OTP (formulaire OTP
       requis : configuration de l'application imposée si absente).
       Entrée : role = rôle de realm qui déclenche l'OTP ; "" : OTP pour tous.
       Sortie YAML : authenticationFlows, authenticatorConfig. */}}
{{- define "kc.mfaFlows" -}}
{{- $role := .role }}
{{- $otp := dict "authenticator" "auth-otp-form" "requirement" "REQUIRED" "priority" 20 "authenticatorFlow" false "autheticatorFlow" false "userSetupAllowed" false }}
{{- $forms := list (dict "authenticator" "auth-username-password-form" "requirement" "REQUIRED" "priority" 10 "authenticatorFlow" false "autheticatorFlow" false "userSetupAllowed" false) }}
{{- $flows := list }}
{{- $configs := list }}
{{- if $role }}
{{- $forms = append $forms (dict "flowAlias" "browser-mfa otp" "requirement" "CONDITIONAL" "priority" 20 "authenticatorFlow" true "autheticatorFlow" true "userSetupAllowed" false) }}
{{- $flows = append $flows (dict
      "alias" "browser-mfa otp" "description" "OTP si l'utilisateur a le rôle déclencheur"
      "providerId" "basic-flow" "topLevel" false "builtIn" false
      "authenticationExecutions" (list
        (dict "authenticator" "conditional-user-role" "authenticatorConfig" "browser-mfa role" "requirement" "REQUIRED" "priority" 10 "authenticatorFlow" false "autheticatorFlow" false "userSetupAllowed" false)
        (set (deepCopy $otp) "priority" 20))) }}
{{- $configs = append $configs (dict "alias" "browser-mfa role" "config" (dict "condUserRole" $role "negate" "false")) }}
{{- else }}
{{- $forms = append $forms $otp }}
{{- end }}
{{- $flows = prepend $flows (dict
      "alias" "browser-mfa forms" "description" "Mot de passe puis OTP"
      "providerId" "basic-flow" "topLevel" false "builtIn" false
      "authenticationExecutions" $forms) }}
{{- $flows = prepend $flows (dict
      "alias" "browser-mfa" "description" "Navigateur : session existante, sinon mot de passe + OTP (keycloak-config)"
      "providerId" "basic-flow" "topLevel" true "builtIn" false
      "authenticationExecutions" (list
        (dict "authenticator" "auth-cookie" "requirement" "ALTERNATIVE" "priority" 10 "authenticatorFlow" false "autheticatorFlow" false "userSetupAllowed" false)
        (dict "authenticator" "identity-provider-redirector" "requirement" "ALTERNATIVE" "priority" 25 "authenticatorFlow" false "autheticatorFlow" false "userSetupAllowed" false)
        (dict "flowAlias" "browser-mfa forms" "requirement" "ALTERNATIVE" "priority" 30 "authenticatorFlow" true "autheticatorFlow" true "userSetupAllowed" false))) }}
{{- toYaml (dict "authenticationFlows" $flows "authenticatorConfig" $configs) }}
{{- end -}}

{{- /* Utilisateur humain : mot de passe initial temporaire (userLabel "initial" : posé
       à la création seulement, jamais réappliqué). Entrée : username, user, extra (dict). */}}
{{- define "kc.user" -}}
{{- $u := .user | default dict }}
{{- $user := merge (deepCopy (.extra | default dict)) (dict
      "username" .username
      "enabled" (ternary $u.enabled true (hasKey $u "enabled"))
      "emailVerified" true
      "credentials" (list (dict
        "type" "password"
        "userLabel" "initial"
        "temporary" true
        "value" "$(env:USER_INITIAL_PASSWORD)"))) }}
{{- with $u.email }}{{ $_ := set $user "email" . }}{{ end }}
{{- with $u.firstName }}{{ $_ := set $user "firstName" . }}{{ end }}
{{- with $u.lastName }}{{ $_ := set $user "lastName" . }}{{ end }}
{{- toYaml $user }}
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
{{- $acc := include "kc.realmAccess" . | fromYaml }}

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
{{- /* SAML : rôles dans un seul attribut multi-valeurs (samlGroupsAttribute), rôles
       renommés en groupe de l'outil (group de la matrice d'accès) */}}
{{- if and (eq $protocol "saml") $c.samlGroupsAttribute }}
{{- $mappers = append $mappers (dict
      "name" "groups"
      "protocol" "saml"
      "protocolMapper" "saml-role-list-mapper"
      "config" (dict "attribute.name" $c.samlGroupsAttribute "attribute.nameformat" "Basic" "single" "true")) }}
{{- range $role, $def := (index $acc.catalog $cid | default dict) }}
{{- with ($def | default dict).group }}
{{- $mappers = append $mappers (dict
      "name" (printf "role-%s" $role)
      "protocol" "saml"
      "protocolMapper" "saml-role-name-mapper"
      "config" (dict "role" (printf "%s.%s" $cid $role) "new.role.name" .)) }}
{{- end }}
{{- end }}
{{- end }}
{{- range $c.protocolMappers }}{{ $mappers = append $mappers . }}{{ end }}
{{- if $attributes }}{{ $_ := set $client "attributes" $attributes }}{{ end }}
{{- if $mappers }}{{ $_ := set $client "protocolMappers" $mappers }}{{ end }}
{{- $client = merge (deepCopy ($c.settings | default dict)) $client }}
{{- $clients = append $clients $client }}
{{- with (index $acc.roles $cid) }}
{{- $roles := list }}
{{- range . }}{{ $roles = append $roles (dict "name" .) }}{{ end }}
{{- $_ := set $clientRoles $cid $roles }}
{{- end }}
{{- end }}
{{- if $clients }}{{ $_ := set $realm "clients" $clients }}{{ end }}

{{- /* Groupes : composition de rôles clients ; mfa -> rôle de realm mfa-required,
       déclencheur du flux browser-mfa */}}
{{- $groups := list }}
{{- $mfa := false }}
{{- range $gname, $g := $acc.groups }}
{{- $group := dict "name" $gname }}
{{- with $g.clientRoles }}{{ $_ := set $group "clientRoles" . }}{{ end }}
{{- if $g.mfa }}
{{- $mfa = true }}
{{- $_ := set $group "realmRoles" (list "mfa-required") }}
{{- end }}
{{- $groups = append $groups $group }}
{{- end }}
{{- if $groups }}{{ $_ := set $realm "groups" $groups }}{{ end }}
{{- $rolesRep := dict }}
{{- if $clientRoles }}{{ $_ := set $rolesRep "client" $clientRoles }}{{ end }}
{{- if $mfa }}
{{- $_ := set $rolesRep "realm" (list (dict "name" "mfa-required" "description" "Code OTP exigé à la connexion (groupes mfa: true)")) }}
{{- $_ := set $realm "browserFlow" "browser-mfa" }}
{{- $realm = merge $realm (include "kc.mfaFlows" (dict "role" "mfa-required") | fromYaml) }}
{{- else }}
{{- $_ := set $realm "browserFlow" "browser" }}
{{- end }}
{{- if $rolesRep }}{{ $_ := set $realm "roles" $rolesRep }}{{ end }}

{{- /* Utilisateurs */}}
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

{{- /* Realm master : client de service de keycloak-config-cli (rôle admin),
       administrateurs nominatifs (OTP obligatoire), compte de démarrage. */}}
{{- define "kc.masterJson" -}}
{{- $root := .root }}
{{- $m := $root.Values.master }}
{{- $cli := $root.Values.keycloak.client }}
{{- $realm := merge (dict "realm" "master" "enabled" true) (deepCopy $root.Values.realmDefaults) }}
{{- $_ := set $realm "clients" (list (dict
      "clientId" $cli.id
      "name" "keycloak-config-cli (GitOps)"
      "enabled" true
      "protocol" "openid-connect"
      "publicClient" false
      "clientAuthenticatorType" "client-secret"
      "secret" "$(env:KEYCLOAK_CLIENTSECRET)"
      "serviceAccountsEnabled" true
      "standardFlowEnabled" false
      "implicitFlowEnabled" false
      "directAccessGrantsEnabled" false)) }}
{{- $users := list (dict "username" (printf "service-account-%s" $cli.id) "enabled" true "serviceAccountClientId" $cli.id "realmRoles" (list "admin")) }}
{{- $users = append $users (dict "username" $root.Values.keycloak.bootstrapAdmin.user "enabled" $m.bootstrapAdminEnabled) }}
{{- range $uname, $u := ($m.admins | default dict) }}
{{- $users = append $users (include "kc.user" (dict "username" $uname "user" $u "extra" (dict "realmRoles" (list "admin"))) | fromYaml) }}
{{- end }}
{{- $_ := set $realm "users" $users }}
{{- if $m.mfa }}
{{- $_ := set $realm "browserFlow" "browser-mfa" }}
{{- $realm = merge $realm (include "kc.mfaFlows" (dict "role" "") | fromYaml) }}
{{- else }}
{{- $_ := set $realm "browserFlow" "browser" }}
{{- end }}
{{- toPrettyJson $realm }}
{{- end -}}

{{- /* Contenu de la ConfigMap : un fichier JSON par realm */}}
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
