{{- /* Flux de connexion "browser-mfa" : session existante, sinon mot de passe puis
       code OTP (configuration de l'application OTP imposée si absente).

       Entrée : dict "role" <rôle de realm qui déclenche l'OTP>
                ""  : OTP pour tout le monde (realm master)
       Sortie (YAML) : authenticationFlows, authenticatorConfig, à fusionner dans le realm.

       Chaque étape porte authenticatorFlow ET autheticatorFlow (sic) : Keycloak lit
       encore l'ancienne orthographe ; sans elle, l'import signale une différence. */}}
{{- define "kc.mfaFlows" -}}
authenticationFlows:
  # Flux principal : cookie de session, ou redirection vers un IdP, ou formulaires
  - alias: browser-mfa
    description: "Navigateur : session existante, sinon mot de passe + OTP (keycloak-config)"
    providerId: basic-flow
    topLevel: true
    builtIn: false
    authenticationExecutions:
      - {authenticator: auth-cookie, requirement: ALTERNATIVE, priority: 10, authenticatorFlow: false, autheticatorFlow: false, userSetupAllowed: false}
      - {authenticator: identity-provider-redirector, requirement: ALTERNATIVE, priority: 25, authenticatorFlow: false, autheticatorFlow: false, userSetupAllowed: false}
      - {flowAlias: browser-mfa forms, requirement: ALTERNATIVE, priority: 30, authenticatorFlow: true, autheticatorFlow: true, userSetupAllowed: false}

  # Formulaires : mot de passe, puis OTP (toujours, ou seulement avec le rôle déclencheur)
  - alias: browser-mfa forms
    description: Mot de passe puis OTP
    providerId: basic-flow
    topLevel: false
    builtIn: false
    authenticationExecutions:
      - {authenticator: auth-username-password-form, requirement: REQUIRED, priority: 10, authenticatorFlow: false, autheticatorFlow: false, userSetupAllowed: false}
      {{- if .role }}
      - {flowAlias: browser-mfa otp, requirement: CONDITIONAL, priority: 20, authenticatorFlow: true, autheticatorFlow: true, userSetupAllowed: false}
      {{- else }}
      - {authenticator: auth-otp-form, requirement: REQUIRED, priority: 20, authenticatorFlow: false, autheticatorFlow: false, userSetupAllowed: false}
      {{- end }}
  {{- if .role }}

  # OTP conditionnel : seulement si l'utilisateur a le rôle déclencheur
  - alias: browser-mfa otp
    description: OTP si l'utilisateur a le rôle déclencheur
    providerId: basic-flow
    topLevel: false
    builtIn: false
    authenticationExecutions:
      - {authenticator: conditional-user-role, authenticatorConfig: browser-mfa role, requirement: REQUIRED, priority: 10, authenticatorFlow: false, autheticatorFlow: false, userSetupAllowed: false}
      - {authenticator: auth-otp-form, requirement: REQUIRED, priority: 20, authenticatorFlow: false, autheticatorFlow: false, userSetupAllowed: false}

authenticatorConfig:
  - alias: browser-mfa role
    config:
      condUserRole: {{ .role }}
      negate: "false"
  {{- else }}

authenticatorConfig: []
  {{- end }}
{{- end -}}
