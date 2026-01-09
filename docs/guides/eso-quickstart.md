# External Secrets Operator - Quick Start

Get ESO + Bitwarden running in 15 minutes.

## Prerequisites

- [ ] OpenShift 4.20 cluster running
- [ ] Bitwarden vault accessible (vault.sigtom.dev)
- [ ] `oc` CLI configured
- [ ] `bw` CLI installed locally
- [ ] ArgoCD managing your GitOps

## Step 1: Install ESO (5 minutes)

### Option A: Via OperatorHub (Recommended)

```bash
# Create namespace
oc create namespace external-secrets

# Install operator via web console:
# 1. OpenShift Console → Operators → OperatorHub
# 2. Search "External Secrets Operator"
# 3. Click Install
# 4. Select "All namespaces on the cluster"
# 5. Click Install
```

### Option B: Via CLI

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: external-secrets-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: external-secrets-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Wait for operator to be ready
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=external-secrets -n external-secrets --timeout=300s
```

## Step 2: Create Bootstrap Secret (5 minutes)

Get Bitwarden session and create a secret:

```bash
# Unlock Bitwarden
bw login
export BW_SESSION=$(bw unlock --raw)

# Create secret in external-secrets namespace
oc create secret generic bitwarden-cli \
  --from-literal=BW_SESSION="$BW_SESSION" \
  -n external-secrets

# Verify
oc get secret bitwarden-cli -n external-secrets
```

**For Production**: Seal this secret with kubeseal and commit to git:

```bash
# Get current secret
oc get secret bitwarden-cli -n external-secrets -o yaml > /tmp/bw-secret.yaml

# Seal it
kubeseal -f /tmp/bw-secret.yaml -w gitops/bootstrap/sealed-secret-bitwarden-cli.yaml

# Commit to git
git add gitops/bootstrap/sealed-secret-bitwarden-cli.yaml
git commit -m "Add Bitwarden CLI bootstrap secret"
git push

# Delete temp file
rm /tmp/bw-secret.yaml
```

## Step 3: Create ClusterSecretStore (2 minutes)

```bash
cat <<EOF | oc apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: bitwarden-store
spec:
  provider:
    bitwarden:
      url: https://vault.sigtom.dev
      cliPath: /usr/local/bin/bw
      auth:
        secretRef:
          credentials:
            name: bitwarden-cli
            namespace: external-secrets
            key: BW_SESSION
EOF

# Verify
oc get clustersecretstore bitwarden-store
```

## Step 4: Test with Example (3 minutes)

### Create test secret in Bitwarden

```bash
# Create a test item
bw get template item | \
  jq '.type = 1 | .name = "test-secret" | .login.password = "hello-from-bitwarden"' | \
  bw encode | \
  bw create item

# Verify
bw get item test-secret
```

### Create ExternalSecret

```bash
# Create test namespace
oc create namespace eso-test

# Create ExternalSecret
cat <<EOF | oc apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: test-secret
  namespace: eso-test
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: bitwarden-store
    kind: ClusterSecretStore
  target:
    name: test-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: test-secret
EOF
```

### Verify Secret Created

```bash
# Check ExternalSecret status
oc get externalsecret test-secret -n eso-test

# Should show:
# NAME          STORE              REFRESH INTERVAL   STATUS   READY
# test-secret   bitwarden-store    1m                 SecretSynced    True

# Check the generated secret
oc get secret test-secret -n eso-test

# View the secret value
oc get secret test-secret -n eso-test -o jsonpath='{.data.password}' | base64 -d
# Should output: hello-from-bitwarden
```

### Test in a Pod

```bash
# Create test pod
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secret-test
  namespace: eso-test
spec:
  containers:
  - name: test
    image: busybox
    command: ['sh', '-c', 'echo "Secret value: \$SECRET_PASSWORD" && sleep 3600']
    env:
    - name: SECRET_PASSWORD
      valueFrom:
        secretKeyRef:
          name: test-secret
          key: password
EOF

# Check logs
oc logs secret-test -n eso-test
# Should show: Secret value: hello-from-bitwarden
```

## Success! 🎉

ESO is now syncing secrets from Bitwarden to OpenShift!

## Real-World Example: Plex Token

Now let's do a real one - migrate Plex token to ESO:

### 1. Ensure Plex token exists in Bitwarden

```bash
# Check if it exists
bw get item plex-claim

# If not, create it
# Get your claim token from https://www.plex.tv/claim/
bw get template item | \
  jq '.type = 1 | .name = "plex-claim" | .login.password = "claim-YOUR-TOKEN-HERE"' | \
  bw encode | \
  bw create item
```

### 2. Create ExternalSecret

```bash
cat <<EOF | oc apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: plex-token
  namespace: media
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-store
    kind: ClusterSecretStore
  target:
    name: plex-token
    creationPolicy: Owner
  data:
    - secretKey: PLEX_CLAIM
      remoteRef:
        key: plex-claim
EOF
```

### 3. Update Plex Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plex
  namespace: media
spec:
  template:
    spec:
      containers:
      - name: plex
        image: plexinc/pms-docker:latest
        env:
          - name: PLEX_CLAIM
            valueFrom:
              secretKeyRef:
                name: plex-token  # Created by ESO
                key: PLEX_CLAIM
```

### 4. Commit to Git

```bash
# Commit the ExternalSecret manifest (NOT the actual secret!)
git add gitops/apps/media/plex/external-secret.yaml
git commit -m "Migrate Plex token to ESO"
git push

# ArgoCD will sync and ESO will create the secret
```

## Troubleshooting

### ExternalSecret shows "SecretSyncedError"

```bash
# Check ExternalSecret status
oc describe externalsecret test-secret -n eso-test

# Common issues:
# 1. Item doesn't exist in Bitwarden
#    → Check: bw get item <item-name>
#
# 2. BW_SESSION expired
#    → Renew: export BW_SESSION=$(bw unlock --raw)
#    → Update secret: oc create secret generic bitwarden-cli \
#                      --from-literal=BW_SESSION="$BW_SESSION" \
#                      -n external-secrets --dry-run=client -o yaml | oc apply -f -
#
# 3. Wrong field referenced
#    → Check available fields: bw get item <item-name> | jq
```

### Secret not updating after Bitwarden change

```bash
# Force refresh
oc annotate externalsecret test-secret -n eso-test \
  force-sync=$(date +%s) --overwrite

# Check refresh interval
oc get externalsecret test-secret -n eso-test -o jsonpath='{.spec.refreshInterval}'

# Reduce for testing
oc patch externalsecret test-secret -n eso-test \
  --type merge -p '{"spec":{"refreshInterval":"30s"}}'
```

### ClusterSecretStore not ready

```bash
# Check status
oc get clustersecretstore bitwarden-store -o yaml

# Check ESO operator logs
oc logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f

# Verify bitwarden-cli secret exists
oc get secret bitwarden-cli -n external-secrets

# Test Bitwarden connection manually
oc run -it --rm bw-test --image=bitwarden/cli --restart=Never -- bash
# Inside pod:
# export BW_SESSION="<your-session>"
# bw list items
```

## Next Steps

1. **Migrate existing apps** - See [Migration Guide](./eso-migration-guide.md)
2. **Set up session renewal** - Automate BW_SESSION rotation
3. **Configure monitoring** - Add Prometheus alerts
4. **Update documentation** - Document new secret workflow for team

## Quick Reference

```bash
# List all ExternalSecrets
oc get externalsecret -A

# Check specific ExternalSecret
oc describe externalsecret <name> -n <namespace>

# Force sync
oc annotate externalsecret <name> -n <namespace> force-sync=$(date +%s) --overwrite

# View generated secret
oc get secret <name> -n <namespace> -o yaml

# Test Bitwarden connection
export BW_SESSION=$(bw unlock --raw)
bw list items

# Renew session in cluster
oc create secret generic bitwarden-cli \
  --from-literal=BW_SESSION="$BW_SESSION" \
  -n external-secrets --dry-run=client -o yaml | oc apply -f -
```

## Resources

- [Full Architecture Guide](../architecture/external-secrets-bitwarden.md)
- [External Secrets Operator Docs](https://external-secrets.io/latest/)
- [Bitwarden CLI Docs](https://bitwarden.com/help/cli/)
