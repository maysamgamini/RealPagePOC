{{/*
Expand the name of the chart.
*/}}
{{- define "n8n-scalable.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "n8n-scalable.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "n8n-scalable.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "n8n-scalable.labels" -}}
helm.sh/chart: {{ include "n8n-scalable.chart" . }}
{{ include "n8n-scalable.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "n8n-scalable.selectorLabels" -}}
app.kubernetes.io/name: {{ include "n8n-scalable.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "n8n-scalable.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "n8n-scalable.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Redis host
*/}}
{{- define "n8n-scalable.redisHost" -}}
{{- if .Values.redis.enabled -}}
{{- include "n8n-scalable.fullname" . }}-redis-master
{{- else -}}
{{- .Values.externalRedis.host -}}
{{- end -}}
{{- end }}

{{/*
Redis port
*/}}
{{- define "n8n-scalable.redisPort" -}}
{{- if .Values.redis.enabled -}}
6379
{{- else -}}
{{- .Values.externalRedis.port -}}
{{- end -}}
{{- end }}

{{/*
Database host
*/}}
{{- define "n8n-scalable.databaseHost" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "n8n-scalable.fullname" . }}-postgresql
{{- else -}}
{{- .Values.externalDatabase.host -}}
{{- end -}}
{{- end }}

{{/*
Database port
*/}}
{{- define "n8n-scalable.databasePort" -}}
{{- if .Values.postgresql.enabled -}}
5432
{{- else -}}
{{- .Values.externalDatabase.port -}}
{{- end -}}
{{- end }}

{{/*
Database name
*/}}
{{- define "n8n-scalable.databaseName" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.database -}}
{{- else -}}
{{- .Values.externalDatabase.database -}}
{{- end -}}
{{- end }}

{{/*
Database username
*/}}
{{- define "n8n-scalable.databaseUsername" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.username -}}
{{- else -}}
{{- .Values.externalDatabase.username -}}
{{- end -}}
{{- end }}

{{/*
Database password secret name
*/}}
{{- define "n8n-scalable.databasePasswordSecret" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "n8n-scalable.fullname" . }}-postgresql
{{- else -}}
{{- .Values.externalDatabase.existingSecret -}}
{{- end -}}
{{- end }}

{{/*
Database password secret key
*/}}
{{- define "n8n-scalable.databasePasswordSecretKey" -}}
{{- if .Values.postgresql.enabled -}}
postgres-password
{{- else -}}
{{- .Values.externalDatabase.existingSecretPasswordKey -}}
{{- end -}}
{{- end }} 