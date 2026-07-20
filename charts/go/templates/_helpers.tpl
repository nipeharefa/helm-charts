{{/*
Expand the name of the chart.
*/}}
{{- define "go.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "go.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "go.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "go.labels" -}}
helm.sh/chart: {{ include "go.chart" . }}
{{ include "go.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "go.selectorLabels" -}}
app.kubernetes.io/name: {{ include "go.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "go.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "go.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the SecretStore managed by this chart.
*/}}
{{- define "go.secretStoreName" -}}
{{- printf "%s-store" (include "go.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Resolve the SecretStoreRef name: use the templated store when this chart creates
one, otherwise fall back to the externally-managed store named in values.
*/}}
{{- define "go.secretStoreRefName" -}}
{{- if and .Values.externalSecret.secretStore.create .Values.externalSecret.secretStore.provider }}
{{- include "go.secretStoreName" . }}
{{- else }}
{{- required "externalSecret.secretStoreRef.name is required when secretStore.create is false" .Values.externalSecret.secretStoreRef.name }}
{{- end }}
{{- end }}

{{/*
Resolve the SecretStoreRef kind.
*/}}
{{- define "go.secretStoreRefKind" -}}
{{- if and .Values.externalSecret.secretStore.create .Values.externalSecret.secretStore.provider }}
{{- .Values.externalSecret.secretStore.kind | default "SecretStore" }}
{{- else }}
{{- .Values.externalSecret.secretStoreRef.kind | default "SecretStore" }}
{{- end }}
{{- end }}

{{/*
The name of the Secret produced by the ExternalSecret (consumed by the
Deployment via envFrom / volumeMount). Defaults to the chart fullname.
*/}}
{{- define "go.externalSecretTargetName" -}}
{{- if .Values.externalSecret.targetName }}
{{- .Values.externalSecret.targetName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "go.fullname" . }}
{{- end }}
{{- end }}

{{/*
Resolve the PersistentVolumeClaim name used by the Deployment:
- when persistence.existingClaim is set, use it verbatim (skip creation)
- otherwise default to <fullname>-<persistence.name>
*/}}
{{- define "go.persistenceClaimName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-%s" (include "go.fullname" .) .Values.persistence.name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Resolve the container port number used to serve metrics. This MUST match the
actual containerPort declared on the Pod: vmagent / victoria-metrics scrape
configs commonly apply `keep_if_equal` between __meta_kubernetes_pod_annotation_prometheus_io_port
and __meta_kubernetes_pod_container_port_number, so any mismatch silently drops
the target. Resolution order: metrics.port (explicit) -> service.ports[0].targetPort
-> service.ports[0].port -> service.port.
*/}}
{{- define "go.metrics.port" -}}
{{- if .Values.metrics.port }}
{{- .Values.metrics.port }}
{{- else if .Values.service.ports }}
{{- $first := index .Values.service.ports 0 }}
{{- default $first.port $first.targetPort }}
{{- else }}
{{- .Values.service.port }}
{{- end }}
{{- end }}
