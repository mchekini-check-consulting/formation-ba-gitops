{{- /* Realm master (values : master) :
         - client de service de keycloak-config-cli (rôle admin), avec lequel l'import se connecte
         - compte de démarrage (activé ou non : master.bootstrapAdminEnabled)
         - administrateurs nominatifs (rôle admin, mot de passe initial temporaire)
         - OTP pour tous si master.mfa
       Entrée : dict "root" $. */}}
{{- define "kc.masterJson" -}}
{{- $root := .root }}
{{- $realm := merge (dict "realm" "master" "enabled" true) (deepCopy $root.Values.realmDefaults) }}
{{- range $key, $value := include "kc.masterContent" $root | fromYaml }}
  {{- $_ := set $realm $key $value }}
{{- end }}
{{- if $root.Values.master.mfa }}
  {{- $realm = merge $realm (include "kc.mfaFlows" (dict "role" "") | fromYaml) }}
{{- end }}
{{- toPrettyJson $realm }}
{{- end -}}

{{- define "kc.masterContent" -}}
{{- $m := .Values.master }}
{{- $cli := .Values.keycloak.client }}
clients:
  - clientId: {{ $cli.id | toJson }}
    name: keycloak-config-cli (GitOps)
    enabled: true
    protocol: openid-connect
    publicClient: false
    clientAuthenticatorType: client-secret
    secret: "$(env:KEYCLOAK_CLIENTSECRET)"
    serviceAccountsEnabled: true
    standardFlowEnabled: false
    implicitFlowEnabled: false
    directAccessGrantsEnabled: false
users:
  - username: {{ printf "service-account-%s" $cli.id | toJson }}
    enabled: true
    serviceAccountClientId: {{ $cli.id | toJson }}
    realmRoles: [admin]
  - username: {{ .Values.keycloak.bootstrapAdmin.user | toJson }}
    enabled: {{ $m.bootstrapAdminEnabled }}
  {{- range $uname, $u := ($m.admins | default dict) }}
  - {{ include "kc.user" (dict "username" $uname "user" $u "extra" (dict "realmRoles" (list "admin"))) | fromYaml | toJson }}
  {{- end }}
browserFlow: {{ ternary "browser-mfa" "browser" (default false $m.mfa) }}
{{- end -}}
