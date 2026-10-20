{{- /*
Configuration effective d'un cluster, depuis databases (values/<common|env>/databases.yaml) :
  defaults  <  clusters.<nom> (plateforme)  ou  projects.<projet> (métier)
Le fichier de l'environnement surcharge le commun (fusion des values par Helm).

Entrée : dict
  Values    : .Values du chart appelant (doit contenir databases)
  name      : nom du Cluster CNPG (= nom de son ServiceAccount, doit finir par -db)
  namespace : namespace du Cluster
  cluster   : clé dans databases.clusters (plateforme)   } un des deux
  project   : clé dans databases.projects (métier)        }
Sortie : YAML { name, namespace, env, s3, cfg, archive, restoreFrom }, à relire avec fromYaml.
  archive     : nom de l'archive S3 du cluster (serverName barman) : <nom> si
                generation = 0, sinon <nom>-g<generation>. Une restauration
                ouvre une nouvelle génération (barman refuse d'écrire dans une
                archive non vide).
  restoreFrom : archive lue par la restauration (restore.enabled) : restore.from,
                sinon la génération précédente.
*/}}
{{- define "pg-lib.config" -}}
{{- $db := required "databases requis (values/common/databases.yaml)" .Values.databases }}
{{- $over := dict }}
{{- if .cluster }}
{{- if not (hasKey ($db.clusters | default dict) .cluster) }}
{{- fail (printf "databases.clusters.%s absent : base non déclarée dans values/common/databases.yaml" .cluster) }}
{{- end }}
{{- $over = index $db.clusters .cluster | default dict }}
{{- else if .project }}
{{- $over = index ($db.projects | default dict) .project | default dict }}
{{- else }}
{{- fail "pg-lib.config : cluster ou project requis" }}
{{- end }}
{{- $cfg := include "pg-lib.merge" (dict "base" ($db.defaults | default dict) "over" $over) | fromYaml }}
{{- if not (hasSuffix "-db" .name) }}
{{- fail (printf "Cluster %s : le nom doit finir par -db (ServiceAccount autorisé par le rôle IRSA des sauvegardes)" .name) }}
{{- end }}
{{- if not $cfg.databases }}
{{- fail (printf "Cluster %s : au moins une base logique requise (databases)" .name) }}
{{- end }}
{{- $gen := int ($cfg.generation | default 0) }}
{{- $archive := .name }}
{{- if gt $gen 0 }}{{ $archive = printf "%s-g%d" .name $gen }}{{ end }}
{{- $restore := $cfg.restore | default dict }}
{{- $_ := set $cfg "restore" $restore }}
{{- $restoreFrom := "" }}
{{- if $restore.enabled }}
{{- if $restore.from }}
{{- $restoreFrom = $restore.from }}
{{- else if eq $gen 0 }}
{{- fail (printf "Cluster %s : restore.enabled demande generation >= 1 (nouvelle archive) ou restore.from" .name) }}
{{- else if eq $gen 1 }}
{{- $restoreFrom = .name }}
{{- else }}
{{- $restoreFrom = printf "%s-g%d" .name (sub $gen 1) }}
{{- end }}
{{- if eq $restoreFrom $archive }}
{{- fail (printf "Cluster %s : restore.from = archive du cluster (%s) ; incrémenter generation" .name $archive) }}
{{- end }}
{{- end }}
{{- $s3 := $db.s3 | default dict }}
{{- if or $cfg.backup.physical.enabled $cfg.backup.logical.enabled $restore.enabled }}
{{- $_ := required "databases.s3.bucket requis (values/<env>/databases.yaml)" $s3.bucket }}
{{- $_ := required "databases.s3.roleArn requis (values/<env>/databases.yaml)" $s3.roleArn }}
{{- end }}
{{- toYaml (dict
      "name" .name
      "namespace" .namespace
      "env" (required "databases.env requis (passé par l'Application)" $db.env)
      "s3" $s3
      "cfg" $cfg
      "archive" $archive
      "restoreFrom" $restoreFrom) }}
{{- end }}

{{- /* Fusion récursive de deux maps (over l'emporte, false et 0 compris :
       mergeOverwrite de sprig ignore les valeurs vides). */}}
{{- define "pg-lib.merge" -}}
{{- $out := deepCopy .base }}
{{- range $k, $v := .over }}
{{- if and (kindIs "map" $v) (kindIs "map" (index $out $k)) }}
{{- $_ := set $out $k (include "pg-lib.merge" (dict "base" (index $out $k) "over" $v) | fromYaml) }}
{{- else }}
{{- $_ := set $out $k $v }}
{{- end }}
{{- end }}
{{- toYaml $out }}
{{- end }}

{{- define "pg-lib.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/component: database
app.kubernetes.io/part-of: cloudnative-pg
app.kubernetes.io/managed-by: pg-lib
cnpg.io/cluster: {{ .name }}
{{- end }}

{{- /* Objet jamais supprimé par ArgoCD (prune, suppression de l'Application,
       erreur de nom ou de chemin) : supprimer une base est un geste manuel. */}}
{{- define "pg-lib.protect" -}}
argocd.argoproj.io/sync-options: Prune=false,Delete=false
{{- end }}

{{- /* Préfixe S3 du cluster : <env>/<namespace> (barman ajoute /<cluster>) */}}
{{- define "pg-lib.s3Prefix" -}}
{{ .env }}/{{ .namespace }}
{{- end }}
