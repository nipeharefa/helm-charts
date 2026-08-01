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

{{/*
==============================================================================
Argo Rollouts helpers
==============================================================================
*/}}

{{/*
The workload kind rendered by this chart. Returns "Rollout" when
rollout.enabled is true, otherwise "Deployment". Used by hpa.yaml's
scaleTargetRef and NOTES.txt so they always target the active workload.
*/}}
{{- define "go.workload.kind" -}}
{{- if .Values.rollout.enabled }}
{{- "Rollout" }}
{{- else }}
{{- "Deployment" }}
{{- end }}
{{- end }}

{{/*
The workload apiVersion matching go.workload.kind. Returns the Argo Rollouts
CRD apiVersion ("argoproj.io/v1alpha1") when rollout.enabled is true,
otherwise the builtin "apps/v1".
*/}}
{{- define "go.workload.apiVersion" -}}
{{- if .Values.rollout.enabled }}
{{- "argoproj.io/v1alpha1" }}
{{- else }}
{{- "apps/v1" }}
{{- end }}
{{- end }}

{{/*
Stable Service name used by the canary Rollout's trafficRouting. Defaults to
the chart fullname so existing ingresses keep working; override via
rollout.canary.stableService.
*/}}
{{- define "go.canary.stableService" -}}
{{- default (include "go.fullname" .) .Values.rollout.canary.stableService }}
{{- end }}

{{/*
Canary Service name used by the canary Rollout's trafficRouting. Defaults to
<fullname>-canary; override via rollout.canary.canaryService.
*/}}
{{- define "go.canary.canaryService" -}}
{{- $name := printf "%s-canary" (include "go.fullname" .) }}
{{- default $name .Values.rollout.canary.canaryService }}
{{- end }}

{{/*
HTTPRoute name referenced by the canary Rollout's gatewayAPI trafficRouting.
Defaults to the chart fullname (the HTTPRoute rendered by this chart); override
via rollout.canary.trafficRouting.plugins."argoproj-labs/gatewayAPI".httpRoute.

Note: the plugin name contains a slash, so the value MUST be accessed via the
`index` function — dotted access (`.plugins.argoproj-labs/gatewayAPI`) would
be parsed as nested keys.
*/}}
{{- define "go.canary.httpRouteName" -}}
{{- $override := "" }}
{{- $tr := default (dict) .Values.rollout.canary.trafficRouting }}
{{- $plugins := default (dict) $tr.plugins }}
{{- with (index $plugins "argoproj-labs/gatewayAPI") }}
{{- $override = .httpRoute }}
{{- end }}
{{- default (include "go.fullname" .) $override }}
{{- end }}

{{/*
Validates rollout.canary.trafficRouting and returns the active provider name.

Returns one of: "" | "nginx" | "alb" | "smi" | "istio" | "traefik" |
"ambassador" | "app-mesh" | "google" | "sfx" | "gatewayapi"

Fails the render when:
  - rollout.canary.trafficRouting.enabled is true but no provider is set
  - rollout.canary.trafficRouting.enabled is true and 2+ providers are set

This helper MUST be invoked (even if its output is discarded) on every code
path that touches trafficRouting so that the validation runs unconditionally.
*/}}
{{- define "go.canary.activeProvider" -}}
{{- $tr := default (dict) .Values.rollout.canary.trafficRouting }}
{{- $providers := list -}}
{{- range $k, $v := $tr }}
{{- if and (ne $k "enabled") (ne $k "plugins") $v }}
{{- $providers = append $providers $k }}
{{- end }}
{{- end }}
{{- $plugins := default (dict) $tr.plugins }}
{{- if (index $plugins "argoproj-labs/gatewayAPI") }}
{{- $providers = append $providers "gatewayapi" }}
{{- end }}
{{- if and $tr.enabled (eq (len $providers) 0) }}
{{- fail "rollout.canary.trafficRouting.enabled is true but no provider is configured. Set exactly one of: nginx | alb | smi | istio | traefik | ambassador | app-mesh | google | sfx | plugins.\"argoproj-labs/gatewayAPI\"" }}
{{- end }}
{{- if gt (len $providers) 1 }}
{{- fail (printf "rollout.canary.trafficRouting: only one provider is allowed, got %d: %v" (len $providers) $providers) }}
{{- end }}
{{- if $providers }}{{ index $providers 0 }}{{ end }}
{{- end }}

{{/*
AnalysisTemplate name rendered by this chart for a given user-supplied entry.
Format: <fullname>-<entry.name>. Deterministic so the Rollout can reference it.
*/}}
{{- define "go.analysis.templateName" -}}
{{- $ctx := .ctx -}}
{{- printf "%s-%s" (include "go.fullname" $ctx) .entry.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Shared PodTemplateSpec used verbatim by both Deployment and Rollout.
Hoisting this into a helper guarantees probes / ports / volumes / config
checksum annotations cannot drift between the two workloads.

NOTE: this helper renders the contents UNDER `template:` (i.e. `metadata:` and
`spec:` of the PodTemplate). Callers must indent appropriately.
*/}}
{{- define "go.podTemplateSpec" -}}
metadata:
  {{- $annotations := merge (dict) (.Values.podAnnotations) }}
  {{- if and .Values.metrics.enabled .Values.metrics.podAnnotations.enabled }}
  {{- $_ := set $annotations "prometheus.io/scrape" "true" }}
  {{- $_ := set $annotations "prometheus.io/port" (include "go.metrics.port" .) }}
  {{- $_ := set $annotations "prometheus.io/path" .Values.metrics.path }}
  {{- $_ := set $annotations "prometheus.io/scheme" .Values.metrics.scheme }}
  {{- end }}
  {{- if .Values.configMap.enabled }}
  {{- $_ := set $annotations "checksum/config" (include (print $.Template.BasePath "/configmap.yaml") . | sha256sum) }}
  {{- end }}
  {{- with $annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "go.labels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- with .Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  serviceAccountName: {{ include "go.serviceAccountName" . }}
  {{- with .Values.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if .Values.initContainers }}
  initContainers:
    {{- if and .Values.configMap.enabled .Values.configMap.mountPath .Values.configMap.mountInInitContainers }}
    {{- range .Values.initContainers }}
    {{- $container := deepCopy . }}
    {{- $configMount := dict "name" "config-volume" "mountPath" $.Values.configMap.mountPath }}
    {{- if $.Values.configMap.subPath }}
    {{- $configMount = set $configMount "subPath" $.Values.configMap.subPath }}
    {{- end }}
    {{- $existingMounts := default (list) $container.volumeMounts }}
    {{- $allMounts := append $existingMounts $configMount }}
    {{- $_ := set $container "volumeMounts" $allMounts }}
    -{{- toYaml $container | nindent 6 }}
    {{- end }}
    {{- else }}
    {{- toYaml .Values.initContainers | nindent 4 }}
    {{- end }}
  {{- end }}
  containers:
    - name: {{ .Chart.Name }}
      {{- with .Values.securityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      {{- with .Values.args }}
      args:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.command }}
      command:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if or (and .Values.configMap.enabled .Values.configMap.envFrom) (and .Values.externalSecret.enabled .Values.externalSecret.envFrom) }}
      envFrom:
        {{- if and .Values.configMap.enabled .Values.configMap.envFrom }}
        - configMapRef:
            name: {{ include "go.fullname" . }}
        {{- end }}
        {{- if and .Values.externalSecret.enabled .Values.externalSecret.envFrom }}
        - secretRef:
            name: {{ include "go.externalSecretTargetName" . }}
        {{- end }}
      {{- end }}
      ports:
        {{- if .Values.service.ports }}
        {{- range .Values.service.ports }}
        - name: {{ .name }}
          containerPort: {{ .targetPort | default .port }}
          protocol: {{ .protocol | default "TCP" }}
        {{- end }}
        {{- else }}
        - name: http
          containerPort: {{ .Values.service.port }}
          protocol: TCP
        {{- end }}
      {{- with .Values.livenessProbe }}
      livenessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.readinessProbe }}
      readinessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if or .Values.volumeMounts (and .Values.configMap.enabled .Values.configMap.mountPath) .Values.persistence.enabled }}
      volumeMounts:
        {{- with .Values.volumeMounts }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- if and .Values.configMap.enabled .Values.configMap.mountPath }}
        - name: config-volume
          mountPath: {{ .Values.configMap.mountPath }}
          {{- if .Values.configMap.subPath }}
          subPath: {{ .Values.configMap.subPath }}
          {{- end }}
        {{- end }}
        {{- if .Values.persistence.enabled }}
        - name: {{ .Values.persistence.name }}
          mountPath: {{ .Values.persistence.mountPath }}
          {{- with .Values.persistence.subPath }}
          subPath: {{ . }}
          {{- end }}
        {{- end }}
      {{- end }}
      {{- with .Values.extraContainers }}
      {{- toYaml . | nindent 4 }}
      {{- end }}
  {{- if or .Values.volumes (and .Values.configMap.enabled .Values.configMap.mountPath) .Values.persistence.enabled }}
  volumes:
    {{- with .Values.volumes }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if and .Values.configMap.enabled .Values.configMap.mountPath }}
    - name: config-volume
      configMap:
        name: {{ include "go.fullname" . }}
    {{- end }}
    {{- if .Values.persistence.enabled }}
    - name: {{ .Values.persistence.name }}
      persistentVolumeClaim:
        claimName: {{ include "go.persistenceClaimName" . }}
    {{- end }}
  {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
