# Known Issues & Remediation

## PrometheusOperatorRejectedResources (Bearer Token File)

**Title:** Fix PrometheusRejectedResources for MetalLB and GitOps Operators

**Description:**
The User Workload Monitoring stack is rejecting `ServiceMonitor` resources from infrastructure operators because they are attempting to use `bearerTokenFile`. This is restricted in newer Prometheus Operator versions or specific UWM configurations that enforce strict security contexts.

**Error Message:**
> "rejected due to invalid configuration: endpoints[0]: it accesses file system via bearer token file which Prometheus specification prohibits"

**Affected Resources:**
1.  `metallb-system/speaker-monitor`
2.  `metallb-system/controller-monitor`
3.  `openshift-gitops-operator/openshift-gitops-operator-metrics-monitor`

**Proposed Solution:**
Update the `ServiceMonitor` definitions to use `bearerTokenSecret` instead of mounting the token file directly, or configure the Monitoring stack to allow this (less recommended).

**Labels:** bug, monitoring, day-2
