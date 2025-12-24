# Specification: Implement Centralized Logging Stack

## Overview
Implement a centralized log aggregation and visualization stack on the OpenShift 4.20 cluster. This will provide a persistent, searchable history of application and infrastructure logs, filling a critical gap in the current observability setup.

## Functional Requirements
- **Log Collection:** Deploy the Red Hat OpenShift Logging Operator to collect logs from all nodes and pods using Vector.
- **Log Storage:** Deploy the Loki Operator to manage a LokiStack as the log backend.
- **Persistence:** Use a Minio S3 bucket on the TrueNAS server for long-term log storage.
- **Search & Visualization:** Integrate Loki with the OpenShift Console "Observe -> Logs" dashboard.
- **Log Types:**
    - **Application Logs:** All container logs from non-infrastructure namespaces (e.g., `media-stack`).
    - **Infrastructure Logs:** Node logs, journald, and control plane component logs.
- **Retention:** Maintain a 30-day log history in Loki.

## Non-Functional Requirements
- **GitOps Managed:** All resources (Operators, LokiStack, ClusterLogForwarder) must be managed via Kustomize and ArgoCD.
- **Security:** Use SealedSecrets for Minio credentials.
- **Efficiency:** Configure Loki in a "Size-S" or similar compact configuration appropriate for a homelab.

## Acceptance Criteria
- [ ] Loki Operator and OpenShift Logging Operator are successfully installed in `openshift-logging`.
- [ ] A `LokiStack` instance is running and successfully connected to the Minio bucket.
- [ ] A `ClusterLogForwarder` is successfully sending Application and Infrastructure logs to Loki.
- [ ] Logs are visible and searchable in the OpenShift Web Console under Observe -> Logs.
- [ ] Logs persist across pod restarts and can be searched back up to 30 days.

## Out of Scope
- **Audit Logs:** Security and API access logs will not be collected at this time.
- **Tracing:** Implementation of Tempo or Jaeger for distributed tracing.
- **Network Observability:** NetObserv operator implementation.
