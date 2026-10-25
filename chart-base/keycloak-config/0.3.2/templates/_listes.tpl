{{- /* Listes calculées depuis realms, utilisées par plusieurs templates.
       Chacune renvoie une liste YAML, à relire avec fromYamlArray. */}}

{{- /* Clients OIDC confidentiels (public: false) : un Secret par client.
       - realm, client
       - secret : Secret Kubernetes keycloak-client-<realm>-<client> (clé client-secret)
       - env    : variable lue par l'import (kc.clientSecretEnv) */}}
{{- define "kc.confidentialClients" -}}
{{- range $realm, $r := .Values.realms }}
{{- range $cid, $c := $r.clients }}
{{- if and (eq ($c.protocol | default "openid-connect") "openid-connect") (not $c.public) }}
- realm: {{ $realm }}
  client: {{ $cid }}
  secret: keycloak-client-{{ $realm }}-{{ $cid }}
  env: {{ include "kc.clientSecretEnv" (dict "realm" $realm "client" $cid) }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- /* Realms à clé de signature fixée (signingKey: true) :
       - realm
       - secret : Secret cert-manager keycloak-realm-<realm>-signing (tls.key, tls.crt) */}}
{{- define "kc.signingRealms" -}}
{{- range $realm, $r := .Values.realms }}
{{- if $r.signingKey }}
- realm: {{ $realm }}
  secret: keycloak-realm-{{ $realm }}-signing
{{- end }}
{{- end }}
{{- end -}}

{{- /* Certificats d'IdP à copier vers un outil SAML (clients avec idpCertificateSecret) :
       - realm
       - source    : Secret de la clé fixée du realm
       - namespace, name : Secret cible qui reçoit le certificat */}}
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

{{- /* Secrets de clients OIDC confidentiels à copier vers l'outil (clients avec
       clientSecretCopy), qui ne peut pas lire le namespace de Keycloak :
       - source          : Secret du client (secret-generator.yaml), clé client-secret
       - namespace, name : Secret cible, même clé client-secret */}}
{{- define "kc.clientSecretCopies" -}}
{{- range $realm, $r := .Values.realms }}
{{- range $cid, $c := $r.clients }}
{{- with $c.clientSecretCopy }}
{{- if or $c.public (ne ($c.protocol | default "openid-connect") "openid-connect") }}
{{- fail (printf "realm %s, client %s : clientSecretCopy réservé aux clients OIDC confidentiels (public: false)" $realm $cid) }}
{{- end }}
- source: keycloak-client-{{ $realm }}-{{ $cid }}
  namespace: {{ required (printf "realm %s, client %s : clientSecretCopy.namespace requis" $realm $cid) .namespace }}
  name: {{ required (printf "realm %s, client %s : clientSecretCopy.name requis" $realm $cid) .name }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
