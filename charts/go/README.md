# go

A Helm chart for Kubernetes that renders either a `Deployment` (default) or an
[Argo Rollouts](https://argo-rollouts.readthedocs.io/) `Rollout`, switchable by
a single value. Canary strategy + optional metric-based analysis is supported.

## Prerequisites

The Rollout workload requires the Argo Rollouts controller installed in the
cluster:

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

The Deployment mode (default) needs nothing beyond standard Kubernetes.

## Install

```bash
# Plain Deployment (default)
helm install my-app ./charts/go

# Argo Rollout with default canary steps (25 -> 50 -> 100, 30s pauses)
helm install my-app ./charts/go --set rollout.enabled=true

# Argo Rollout with metric-based gating against VictoriaMetrics
helm install my-app ./charts/go -f values.rollout.yaml
```

## Workload toggle

| `rollout.enabled` | Workload kind rendered          | HPA `scaleTargetRef` |
|-------------------|---------------------------------|----------------------|
| `false` (default) | `Deployment` (`apps/v1`)        | Deployment           |
| `true`            | `Rollout` (`argoproj.io/v1alpha1`) | Rollout           |

The two are mutually exclusive: enabling `rollout.enabled` removes the
Deployment from the rendered output. Both workloads share the same pod template
(ports, probes, volumes, config checksum annotations, etc.) via a single
`go.podTemplateSpec` helper, so behaviour cannot drift between them.

### Migrating an existing release from Deployment → Rollout

Helm does not delete resources that disappear from the chart, so the first
`helm upgrade` that flips `rollout.enabled=true` leaves the old Deployment in
place. Remove it manually after the upgrade:

```bash
helm upgrade my-app ./charts/go --set rollout.enabled=true
kubectl delete deployment my-app -n <namespace>
```

## Canary strategy

The Rollout ships with sane defaults (`maxSurge: 25%`, `maxUnavailable: 0`).
Customise the step sequence via `rollout.canary.steps`:

```yaml
rollout:
  enabled: true
  canary:
    maxSurge: "25%"
    maxUnavailable: 0
    steps:
      - setWeight: 10
      - pause: {}              # manual promotion via `kubectl argo rollouts promote`
      - setWeight: 30
      - pause: { duration: 5m }
      - setWeight: 100
```

Full step reference: https://argo-rollouts.readthedocs.io/en/stable/features/canary/

## Traffic routing (stable + canary Services)

Out of the box the canary shifts weight purely by adjusting ReplicaSet sizes
(no traffic splitting). To shift at the traffic layer, set
`rollout.canary.trafficRouting` to a provider. The chart then renders **two**
Services — a stable one (named `<release>` by default) and a canary one
(`<release>-canary`) — and injects their names into the Rollout:

```yaml
rollout:
  enabled: true
  canary:
    trafficRouting:
      nginx:
        stableIngress: primary
```

Supported providers: `nginx`, `alb`, `smi`, `istio`, `traefik`, `ambassador`,
`app-mesh`, `google`, `sfx`, `gatewayAPI` — see
https://argo-rollouts.readthedocs.io/en/stable/features/traffic-management/

The chart does **not** provision the upstream routing object itself (the nginx
Ingress, the Istio VirtualService, etc.) — bring your own. Only the stable +
canary Services and the Rollout's `trafficRouting` block are templated.

**Exception — Gateway API:** when `rollout.canary.trafficRouting.gatewayAPI` is
set together with `httpRoute.enabled: true`, the chart renders the HTTPRoute
itself with dual `backendRefs` (stable + canary). See
[Gateway API traffic splitting](#gateway-api-traffic-splitting) below.

### Gateway API traffic splitting

[Gateway API](https://gateway-api.sigs.k8s.io/) is supported natively via Argo
Rollouts' `gatewayAPI` provider (stable since Argo Rollouts v1.5). Unlike the
other providers, the chart renders the routing object itself (the HTTPRoute)
with **two `backendRefs`** pointing at the auto-provisioned stable and canary
Services. Argo Rollouts patches the weights at runtime as the canary
progresses.

Supported Gateway controllers (any that implement the Gateway API HTTPRoute
weight-based splitting contract):

- Envoy Gateway
- Istio
- GKE Gateway
- Kong Gateway
- nginx Gateway Fabric
- Cilium
- (others implementing the same contract)

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: my-gateway
      sectionName: http
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /

rollout:
  enabled: true
  canary:
    trafficRouting:
      gatewayAPI:
        # httpRoute: ""    # defaults to chart fullname (the HTTPRoute above)
        # namespace: ""   # defaults to the Rollout's namespace
    steps:
      - setWeight: 20
      - pause: { duration: 2m }
      - setWeight: 100
```

Rendered HTTPRoute (initial state — Argo patches the weights during canary):

```yaml
spec:
  rules:
    - matches: [...]
      backendRefs:
        - name: app            # stable Service
          port: 80
          weight: 100
        - name: app-canary     # canary Service
          port: 80
          weight: 0
```

Notes:

- **Both `httpRoute.enabled: true` AND `rollout.canary.trafficRouting.gatewayAPI` must be set.** Either alone renders a single-backend HTTPRoute.
- **`gatewayAPI.httpRoute` defaults to the chart fullname.** Override only when pointing at an externally-managed HTTPRoute (in which case disable `httpRoute.enabled` and supply your own dual-backend HTTPRoute).
- **Cross-namespace HTTPRoutes**: set `gatewayAPI.namespace` if the HTTPRoute lives outside the Rollout's namespace. The chart renders HTTPRoutes in the release namespace.
- **TCPRoute / GRPCRoute** are out of scope — chart renders HTTPRoute only.

## Analysis (Prometheus / VictoriaMetrics)

Analysis is **off by default**. Enable it to gate canary progression on
metrics. The chart renders `AnalysisTemplate` CRDs and references them from
the Rollout.

VictoriaMetrics is wire-compatible with the `prometheus` provider — point
`address` at your VM query endpoint. For the multi-tenant cluster version the
tenant ID lives in the URL path: `http://vmselect.monitoring:8481/select/<tenantID>/prometheus`.
For single-node VM: `http://victoriametrics:8428`. Stick to standard PromQL
inside `query`; MetricsQL-specific functions cannot be parsed by Argo.

Two wiring modes are supported (`rollout.analysis.mode`):

- **`step`** (default) — inserts an `analysis` step before each `setWeight`
  in `rollout.canary.steps`. The canary pauses until the metric passes; on
  `failureLimit` breaches the rollout aborts and rolls back.
- **`background`** — runs the analysis continuously for the entire canary.
  Useful for fast-fail detection on metrics that don't depend on canary weight.

```yaml
rollout:
  enabled: true
  analysis:
    enabled: true
    mode: step                 # step | background
    args:
      - name: service-name
        value: my-app
    templates:
      - name: success-rate
        metrics:
          - name: success-rate
            interval: 1m
            successCondition: result[0] >= 0.95
            failureLimit: 2
            provider:
              prometheus:
                # VictoriaMetrics cluster version, tenant 0
                address: http://vmselect.monitoring:8481/select/0/prometheus
                query: |
                  sum(rate(http_requests_total{status!~"5.."}[2m]))
                  / sum(rate(http_requests_total[2m]))
```

Setting `rollout.analysis.enabled: false` removes all AnalysisTemplates and the
Rollout's analysis references; the canary advances purely via `steps`.

## Autoscaling

HPA works in both modes. When `autoscaling.enabled: true`, the chart omits
`spec.replicas` from the workload and the HPA's `scaleTargetRef` is wired to
whichever workload is active (Deployment or Rollout). Note: when combining HPA
with a canary Rollout, Argo recommends letting the Rollout drive canary weight
and the HPA drive only the stable ReplicaSet size — see
https://argo-rollouts.readthedocs.io/en/stable/features/canary/#hpas

## Values

| Key                                        | Default                              | Description                                                                 |
|--------------------------------------------|--------------------------------------|-----------------------------------------------------------------------------|
| `replicaCount`                             | `1`                                  | Replicas when neither rollout nor autoscaling is active.                    |
| `rollout.enabled`                          | `false`                              | Render a Rollout instead of a Deployment.                                   |
| `rollout.replicas`                         | `1`                                  | Replicas for the Rollout (falls back to `replicaCount`).                   |
| `rollout.revisionHistoryLimit`             | `10`                                 | Rollout revision history limit.                                             |
| `rollout.canary.maxSurge`                  | `"25%"`                              | Canary `maxSurge`.                                                          |
| `rollout.canary.maxUnavailable`            | `0`                                  | Canary `maxUnavailable`.                                                    |
| `rollout.canary.steps`                     | (see `values.yaml`)                  | Ordered canary step list (setWeight / pause / experiment / analysis / ...). |
| `rollout.canary.trafficRouting`            | `{}`                                 | Traffic provider config (nginx/alb/istio/gatewayAPI/...). Empty = ReplicaSet canary.  |
| `rollout.canary.trafficRouting.gatewayAPI.httpRoute` | `""`                       | HTTPRoute name for the gatewayAPI provider. Defaults to `<fullname>`.       |
| `rollout.canary.trafficRouting.gatewayAPI.namespace` | `""`                       | Namespace of the HTTPRoute (gatewayAPI provider). Defaults to Rollout ns.   |
| `rollout.canary.stableService`             | `""`                                 | Override stable Service name (default `<fullname>`).                       |
| `rollout.canary.canaryService`             | `""`                                 | Override canary Service name (default `<fullname>-canary`).                |
| `rollout.analysis.enabled`                 | `false`                              | Render AnalysisTemplates and wire them into the Rollout.                    |
| `rollout.analysis.mode`                    | `step`                               | `step` (between setWeight) or `background` (continuous).                   |
| `rollout.analysis.args`                    | `[]`                                 | Args passed to every AnalysisTemplate invocation.                          |
| `rollout.analysis.templates[].name`        | —                                    | Unique template name; CRD is rendered as `<fullname>-<name>`.              |
| `rollout.analysis.templates[].metrics`     | —                                    | Argo Rollouts metric spec (required).                                       |
| `rollout.analysis.templates[].args`        | `[]`                                 | Args scoped to this single template.                                        |
| `autoscaling.enabled`                      | `false`                              | Render HPA targeting whichever workload is active.                          |
| `service.enabled`                          | `true`                               | Render Service(s).                                                          |
| `image.*`, `service.*`, probes, etc.       | (see `values.yaml`)                  | Shared by both Deployment and Rollout via `go.podTemplateSpec`.            |

Full defaults: [`values.yaml`](values.yaml).

## Verifying templates locally

```bash
# Render Deployment mode
helm template app ./charts/go

# Render Rollout mode
helm template app ./charts/go --set rollout.enabled=true

# Render Rollout + step analysis (writes AnalysisTemplate + references it)
helm template app ./charts/go -f your-values.yaml

# Lint
helm lint ./charts/go
```
