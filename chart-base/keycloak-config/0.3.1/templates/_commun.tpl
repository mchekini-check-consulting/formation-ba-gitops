{{- /* Noms, labels et annotations communs à tous les objets du chart. */}}

{{- define "kc.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kc.labels" -}}
app.kubernetes.io/name: keycloak-config
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- /* Annotations d'un hook ArgoCD : exécuté à chaque synchronisation, supprimé
       une fois réussi. Entrée : dict "phase" (PreSync | PostSync) "wave" (texte). */}}
{{- define "kc.hook" -}}
argocd.argoproj.io/hook: {{ .phase }}
argocd.argoproj.io/sync-wave: {{ .wave | quote }}
argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded
{{- end -}}

{{- /* Variable d'environnement qui porte le secret d'un client OIDC confidentiel,
       lue par l'import : CLIENT_SECRET_<REALM>_<CLIENT> (majuscules, - et . -> _).
       Entrée : dict "realm" "client". */}}
{{- define "kc.clientSecretEnv" -}}
CLIENT_SECRET_{{ printf "%s_%s" .realm .client | upper | replace "-" "_" | replace "." "_" }}
{{- end -}}
