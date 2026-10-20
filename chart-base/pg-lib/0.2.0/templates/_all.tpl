{{- /*
Tous les objets d'un cluster : le Cluster, ses bases logiques et leurs
sauvegardes. Seul point d'entrée des charts appelants (pg-cluster,
charts-ba-formations) : une base ne peut pas exister sans sa configuration
de sauvegarde.
Entrée : sortie de pg-lib.config.
*/}}
{{- define "pg-lib.all" -}}
{{- $ctx := . }}
{{- $c := .cfg }}
---
{{ include "pg-lib.cluster" $ctx }}
{{- if or $c.backup.physical.enabled $c.restore.enabled }}
---
{{ include "pg-lib.objectStore" $ctx }}
{{- end }}
{{- /* Pas de sauvegarde planifiée pendant une restauration (pas d'archivage) ;
       recréée ensuite, avec une première sauvegarde immédiate. */}}
{{- if and $c.backup.physical.enabled (not $c.restore.enabled) }}
---
{{ include "pg-lib.scheduledBackup" $ctx }}
{{- end }}
{{- range $db, $dbCfg := $c.databases }}
---
{{ include "pg-lib.database" (dict "ctx" $ctx "db" $db) }}
{{- $logical := include "pg-lib.merge" (dict "base" $c.backup.logical "over" (($dbCfg | default dict).logical | default dict)) | fromYaml }}
{{- if $logical.enabled }}
---
{{ include "pg-lib.dumpCronJob" (dict "ctx" $ctx "db" $db "logical" $logical) }}
{{- end }}
{{- end }}
{{- end }}
