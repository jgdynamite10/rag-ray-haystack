{{- define "rag-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rag-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" (include "rag-app.name" .) .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "rag-app.backendServiceAccountName" -}}
{{- if .Values.backend.serviceAccount.name -}}
{{- .Values.backend.serviceAccount.name -}}
{{- else -}}
{{- printf "%s-backend" (include "rag-app.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
