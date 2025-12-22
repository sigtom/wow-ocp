# Plan: Implement Centralized Logging Stack

## Phase 1: Foundation & Operators [checkpoint: e4b812b]
- [x] Task: Create `infrastructure/logging/base` directory structure 183b865
- [x] Task: Deploy Red Hat OpenShift Logging Operator via Subscription 0af6ad7
- [x] Task: Deploy Loki Operator via Subscription 2e08c30
- [x] Task: Create `openshift-logging` namespace and necessary RBAC f8a2db4
- [x] Task: Conductor - User Manual Verification 'Phase 1: Foundation & Operators' (Protocol in workflow.md) e4b812b

## Phase 2: Storage & Secrets [checkpoint: 7a6baf8]
- [x] Task: Create SealedSecret for Minio S3 credentials in `openshift-logging` 35c7dcf
- [x] Task: Create LokiStack storage secret manifest 35c7dcf
- [x] Task: Conductor - User Manual Verification 'Phase 2: Storage & Secrets' (Protocol in workflow.md) 7a6baf8

## Phase 3: LokiStack Deployment [checkpoint: 6654171]
- [x] Task: Deploy `LokiStack` instance (Size-S) using Minio storage 2746f04
- [x] Task: Verify LokiStack pods are healthy and connected to Minio 2b5d8de
- [x] Task: Conductor - User Manual Verification 'Phase 3: LokiStack Deployment' (Protocol in workflow.md) 6654171

## Phase 4: Log Collection & Console Integration
- [x] Task: Deploy `ClusterLogging` instance to enable Console integration ef85803
- [ ] Task: Deploy `ClusterLogForwarder` to send Application and Infrastructure logs to Loki
- [ ] Task: Verify logs are appearing in OpenShift Console -> Observe -> Logs
- [ ] Task: Verify 30-day retention configuration is active
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Log Collection & Console Integration' (Protocol in workflow.md)
