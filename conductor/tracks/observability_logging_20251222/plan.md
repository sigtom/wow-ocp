# Plan: Implement Centralized Logging Stack

## Phase 1: Foundation & Operators
- [x] Task: Create `infrastructure/logging/base` directory structure 183b865
- [x] Task: Deploy Red Hat OpenShift Logging Operator via Subscription 0af6ad7
- [x] Task: Deploy Loki Operator via Subscription 2e08c30
- [x] Task: Create `openshift-logging` namespace and necessary RBAC f8a2db4
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Foundation & Operators' (Protocol in workflow.md)

## Phase 2: Storage & Secrets
- [ ] Task: Create SealedSecret for Minio S3 credentials in `openshift-logging`
- [ ] Task: Create LokiStack storage secret manifest
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Storage & Secrets' (Protocol in workflow.md)

## Phase 3: LokiStack Deployment
- [ ] Task: Deploy `LokiStack` instance (Size-S) using Minio storage
- [ ] Task: Verify LokiStack pods are healthy and connected to Minio
- [ ] Task: Conductor - User Manual Verification 'Phase 3: LokiStack Deployment' (Protocol in workflow.md)

## Phase 4: Log Collection & Console Integration
- [ ] Task: Deploy `ClusterLogging` instance to enable Console integration
- [ ] Task: Deploy `ClusterLogForwarder` to send Application and Infrastructure logs to Loki
- [ ] Task: Verify logs are appearing in OpenShift Console -> Observe -> Logs
- [ ] Task: Verify 30-day retention configuration is active
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Log Collection & Console Integration' (Protocol in workflow.md)
