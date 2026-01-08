# Runbook 010: Sealed Secrets Decryption Failures

**Frequency:** Occasional (during secret rotation, controller issues)  
**Impact:** High - Apps cannot start without secrets  
**Last Occurred:** Various (secret management operations)  
**MTTR:** 5-30 minutes

---

## Symptoms

- SealedSecret exists but regular Secret not created
- Pod fails to start with: `secret "X" not found`
- SealedSecret controller logs show decryption errors
- Certificate mismatch warnings

**Quick Check:**
```bash
# Check if SealedSecret exists
oc get sealedsecret -n <namespace>

# Check if regular Secret was created
oc get secret -n <namespace>

# Check SealedSecret status
oc describe sealedsecret <sealed-secret-name> -n <namespace>
```

---

## Root Cause Analysis

### Common Causes (Priority Order)

1. **Wrong Public Certificate Used for Sealing** (40% of cases)
   - Sealed with old/different certificate
   - Public cert not synced from controller
   - Multiple clusters, used wrong cert

2. **SealedSecret Controller Not Running** (25% of cases)
   - Controller pod crashed
   - Controller in wrong namespace
   - RBAC issues preventing unsealing

3. **Sealed in Wrong Scope** (15% of cases)
   - Namespace mismatch (sealed for different namespace)
   - Cluster-wide scope but referenced in wrong way
   - Name mismatch between SealedSecret and expected Secret

4. **Certificate Rotation Issues** (10% of cases)
   - Controller cert rotated, old sealed secrets invalid
   - Missing old cert in controller (can't decrypt old secrets)

5. **Malformed SealedSecret Manifest** (10% of cases)
   - Invalid base64 in `encryptedData`
   - YAML syntax error
   - Corrupted during copy/paste

---

## Diagnosis Steps

### Step 1: Check SealedSecret and Secret Status
```bash
# List SealedSecrets
oc get sealedsecret -n <namespace>

# List regular Secrets
oc get secret -n <namespace>

# Describe SealedSecret for events
oc describe sealedsecret <sealed-secret-name> -n <namespace>
```

**Expected:**
- SealedSecret exists
- Matching Secret exists with same name
- No error events

**Problem:**
- SealedSecret exists but Secret missing
- Events show: `Failed to unseal: decryption error`

### Step 2: Check SealedSecret Controller Status
```bash
# Find controller pod
oc get pods -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets

# Check logs
oc logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets --tail=100 | grep <sealed-secret-name>
```

**Common Log Patterns:**

| Log Message | Cause |
|-------------|-------|
| `no key could decrypt secret` | Wrong cert used or cert rotated |
| `cannot find Secret` | Namespace/name mismatch |
| `failed to unseal: invalid ciphertext` | Corrupted SealedSecret data |
| `Error updating secret` | RBAC issue, controller can't create Secret |

### Step 3: Verify Public Certificate
```bash
# Get current public cert from controller
oc get secret -n sealed-secrets sealed-secrets-key -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/controller-cert.pem

# Compare with local cert
diff pub-sealed-secrets.pem /tmp/controller-cert.pem
```

**Expected:** Files are identical  
**Problem:** Files differ (sealed with wrong cert)

### Step 4: Check Scope and Namespace
```bash
oc get sealedsecret <sealed-secret-name> -n <namespace> -o yaml | grep -A 3 "annotations:"
```

**Expected Annotations:**
```yaml
annotations:
  sealedsecrets.bitnami.com/namespace-wide: "true"
  # OR
  sealedsecrets.bitnami.com/cluster-wide: "true"
```

**Scope Types:**
1. **Strict (default):** Secret must be in same namespace with same name
2. **Namespace-wide:** Secret can have any name, but must be in sealed namespace
3. **Cluster-wide:** Secret can be in any namespace with any name

### Step 5: Validate SealedSecret Format
```bash
# Validate YAML syntax
oc apply -f <sealed-secret>.yaml --dry-run=server
```

**Expected:** `created (dry run)`  
**Problem:** YAML parsing error or field validation failure

---

## Resolution by Root Cause

### Fix 1: Wrong Public Certificate (Re-Seal with Correct Cert)

**Symptom:**
- Controller logs: `no key could decrypt secret`
- Public cert differs between local and controller

**Resolution:**

1. **Fetch current public cert:**
```bash
oc get secret -n sealed-secrets sealed-secrets-key -o jsonpath='{.data.tls\.crt}' | base64 -d > pub-sealed-secrets.pem
```

2. **Commit to Git (if not already):**
```bash
git add pub-sealed-secrets.pem
git commit -m "fix: update sealed-secrets public cert"
git push origin main
```

3. **Re-seal the secret:**
```bash
# Recreate raw secret
oc create secret generic <secret-name> \
  --from-literal=KEY=VALUE \
  --dry-run=client -o yaml > /tmp/raw-secret.yaml

# Seal with correct cert
kubeseal --cert pub-sealed-secrets.pem \
  --format yaml < /tmp/raw-secret.yaml \
  > apps/<app-name>/base/<sealed-secret-name>.yaml

# Cleanup
rm /tmp/raw-secret.yaml

# Commit
git add apps/<app-name>/base/<sealed-secret-name>.yaml
git commit -m "fix: re-seal secret with correct certificate"
git push origin main

# Sync
argocd app sync <app-name>
```

4. **Verify Secret creation:**
```bash
oc get secret <secret-name> -n <namespace>
# Should exist now
```

### Fix 2: SealedSecret Controller Not Running

**Symptom:**
- No controller pods in `sealed-secrets` namespace
- Controller pods in `CrashLoopBackOff`

**Resolution:**

1. **Check controller deployment:**
```bash
oc get deployment -n sealed-secrets
oc get pods -n sealed-secrets
```

2. **If missing, redeploy via ArgoCD:**
```bash
argocd app sync sealed-secrets
```

3. **If crashing, check logs:**
```bash
oc logs -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets --tail=100
```

**Common Issues:**
- **RBAC:** Controller can't access Secrets
- **Certificate:** Private key missing or corrupted
- **Resource limits:** OOMKilled

4. **Check controller RBAC:**
```bash
oc get clusterrolebinding sealed-secrets-controller
```

**Expected:**
```yaml
roleRef:
  kind: ClusterRole
  name: secrets-unsealer
subjects:
  - kind: ServiceAccount
    name: sealed-secrets-controller
    namespace: sealed-secrets
```

5. **Restart controller if healthy:**
```bash
oc delete pod -n sealed-secrets -l app.kubernetes.io/name=sealed-secrets
```

### Fix 3: Namespace/Name Mismatch (Wrong Scope)

**Symptom:**
- Controller logs: `secret not found` or `namespace mismatch`
- SealedSecret in one namespace, but Secret expected in another

**Resolution:**

**Understand Scope:**

**Strict (default) - Most secure:**
```bash
# Seal for specific namespace AND name
kubeseal --cert pub-sealed-secrets.pem \
  --namespace <target-namespace> \
  --name <secret-name> \
  --format yaml < raw-secret.yaml > sealed-secret.yaml
```

**Namespace-wide - More flexible:**
```bash
# Seal for specific namespace, any name
kubeseal --cert pub-sealed-secrets.pem \
  --namespace-wide \
  --namespace <target-namespace> \
  --format yaml < raw-secret.yaml > sealed-secret.yaml
```

**Cluster-wide - Most flexible (use sparingly):**
```bash
# Can be used in any namespace
kubeseal --cert pub-sealed-secrets.pem \
  --scope cluster-wide \
  --format yaml < raw-secret.yaml > sealed-secret.yaml
```

**Fix Mismatch:**

1. **Check current scope:**
```bash
oc get sealedsecret <sealed-secret-name> -n <namespace> -o yaml | grep -E "namespace-wide|cluster-wide"
```

2. **Re-seal with correct scope:**
```bash
# Example: Seal for specific namespace
oc create secret generic db-password \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml > /tmp/raw-secret.yaml

kubeseal --cert pub-sealed-secrets.pem \
  --namespace media-stack \
  --name db-password \
  --format yaml < /tmp/raw-secret.yaml \
  > apps/media-stack/base/db-password-sealed.yaml

rm /tmp/raw-secret.yaml
```

3. **Commit and sync:**
```bash
git add apps/media-stack/base/db-password-sealed.yaml
git commit -m "fix: seal secret with correct namespace scope"
git push origin main

argocd app sync media-stack
```

### Fix 4: Certificate Rotation (Old Secrets Can't Decrypt)

**Symptom:**
- SealedSecrets created before rotation fail to decrypt
- New secrets work, old secrets don't

**Explanation:**
When controller certificate rotates, it generates a new keypair. By default, controller keeps old private keys to decrypt old secrets.

**Resolution:**

1. **Verify controller has old keys:**
```bash
oc get secrets -n sealed-secrets | grep sealed-secrets-key
```

**Expected:**
```
sealed-secrets-key        kubernetes.io/tls       3      180d
sealed-secrets-key-XXXXX  kubernetes.io/tls       3      90d
sealed-secrets-key-YYYYY  kubernetes.io/tls       3      1d
```

**If old keys missing:** They were deleted. Must re-seal all secrets.

2. **Re-seal all secrets with current certificate:**

**Script:** `scripts/reseal-all-secrets.sh`

```bash
#!/bin/bash
set -e

echo "Re-sealing all SealedSecrets with current certificate..."

# Get current cert
oc get secret -n sealed-secrets sealed-secrets-key -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/current-cert.pem

# Find all SealedSecret manifests
find apps/ infrastructure/ -name "*sealed-secret*.yaml" -o -name "*sealed*.yaml" | while read file; do
  echo "Processing $file..."
  
  # This is complex - may need manual intervention per secret
  # For each secret, you need to:
  # 1. Retrieve original plaintext (from password manager/vault)
  # 2. Re-seal with current cert
  # 3. Commit new sealed version
  
  echo "  → Manual intervention required: re-seal and commit"
done

rm /tmp/current-cert.pem
echo "✓ Review complete. Re-seal and commit updated secrets."
```

**⚠️ WARNING:** This requires access to original plaintext values.

### Fix 5: Malformed SealedSecret (Corrupted Data)

**Symptom:**
- Controller logs: `invalid ciphertext` or `base64 decode error`
- Recent copy/paste or manual edit of SealedSecret

**Resolution:**

1. **Validate base64 encoding:**
```bash
oc get sealedsecret <sealed-secret-name> -n <namespace> -o jsonpath='{.spec.encryptedData.KEY}' | base64 -d > /dev/null
# If error: invalid base64
```

2. **Re-seal from scratch:**
```bash
# DO NOT try to manually fix encrypted data
# Re-create from plaintext source

oc create secret generic <secret-name> \
  --from-literal=KEY=<original-value> \
  --dry-run=client -o yaml > /tmp/raw-secret.yaml

kubeseal --cert pub-sealed-secrets.pem \
  --namespace <namespace> \
  --format yaml < /tmp/raw-secret.yaml \
  > <sealed-secret-file>.yaml

rm /tmp/raw-secret.yaml
```

---

## Prevention

### 1. Always Use Correct Public Certificate

**Store in Git root:**
```
wow-ocp/
├── pub-sealed-secrets.pem  # ← Public cert here
├── apps/
├── infrastructure/
└── scripts/
```

**Fetch Command (Add to README):**
```bash
# Get current public cert from cluster
oc get secret -n sealed-secrets sealed-secrets-key \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > pub-sealed-secrets.pem
```

### 2. Use Makefile for Sealing Secrets

**File:** `Makefile`

```makefile
.PHONY: seal-secret
seal-secret:
	@read -p "Namespace: " NS; \
	read -p "Secret Name: " NAME; \
	read -p "Key: " KEY; \
	read -s -p "Value: " VALUE; \
	echo ""; \
	kubectl create secret generic $$NAME \
	  --namespace=$$NS \
	  --from-literal=$$KEY=$$VALUE \
	  --dry-run=client -o yaml | \
	kubeseal --cert pub-sealed-secrets.pem \
	  --namespace $$NS \
	  --format yaml > apps/$$NS/base/$$NAME-sealed.yaml && \
	echo "✓ Sealed secret created: apps/$$NS/base/$$NAME-sealed.yaml"
```

**Usage:**
```bash
make seal-secret
# Prompts for namespace, name, key, value
# Outputs sealed secret file
```

### 3. Document Secret Inventory

**File:** `docs/secrets-inventory.md`

```markdown
# Secrets Inventory

## Media Stack
- `rclone-config-sealed` - Rclone configuration (Zurg + TorBox)
- `real-debrid-api-sealed` - Real-Debrid API key
- `torbox-api-sealed` - TorBox API key

## Vaultwarden
- `vaultwarden-db-sealed` - PostgreSQL credentials
- `vaultwarden-admin-token-sealed` - Admin panel access token

## Cert-Manager
- `cloudflare-api-token-sealed` - Cloudflare DNS-01 challenge token

## Backup (OADP)
- `oadp-cloud-credentials-sealed` - MinIO S3 credentials
```

**Benefit:** Know what needs re-sealing after cert rotation.

### 4. Automate Certificate Backup

**Script:** `scripts/backup-sealed-secrets-cert.sh`

```bash
#!/bin/bash
set -e

BACKUP_DIR="$HOME/.sealed-secrets-backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%Y%m%d-%H%M%S)

# Backup private key (CRITICAL - never commit to Git)
oc get secret -n sealed-secrets sealed-secrets-key \
  -o jsonpath='{.data.tls\.key}' | base64 -d \
  > "$BACKUP_DIR/sealed-secrets-key-$DATE.pem"

# Backup public cert (safe to commit to Git)
oc get secret -n sealed-secrets sealed-secrets-key \
  -o jsonpath='{.data.tls\.crt}' | base64 -d \
  > "$BACKUP_DIR/sealed-secrets-cert-$DATE.pem"

echo "✓ Backed up to: $BACKUP_DIR/"
echo "  Private key: sealed-secrets-key-$DATE.pem"
echo "  Public cert: sealed-secrets-cert-$DATE.pem"
echo ""
echo "⚠️  CRITICAL: Store private key in secure vault (1Password, etc.)"
```

**Run monthly:**
```bash
./scripts/backup-sealed-secrets-cert.sh
```

---

## Troubleshooting Decision Tree

```
SealedSecret not creating Secret
    │
    ├─ Controller pods running?
    │   ├─ No → Check deployment, restart controller
    │   └─ Yes → Continue
    │
    ├─ Controller logs show "no key could decrypt"?
    │   └─ Yes → Wrong cert used, re-seal (Fix 1)
    │
    ├─ Controller logs show "namespace mismatch"?
    │   └─ Yes → Wrong scope, re-seal (Fix 3)
    │
    ├─ Controller logs show "invalid ciphertext"?
    │   └─ Yes → Corrupted data, re-seal (Fix 5)
    │
    └─ Controller logs show "cannot create Secret"?
        └─ Yes → RBAC issue, check permissions
```

---

## Emergency: Lost Private Key

**If sealed-secrets controller private key is lost:**

1. **Cannot decrypt existing SealedSecrets**
2. **Must re-seal all secrets from original plaintext**
3. **This is why backup is critical**

**Recovery Process:**

1. Deploy new SealedSecrets controller (generates new keypair)
2. Get new public cert
3. Re-seal ALL secrets from original sources
4. Commit and sync

**Time:** 2-4 hours depending on number of secrets

**Prevention:** Backup private key to secure vault monthly.

---

## Related Issues

- **Issue:** Secret rotation during Vaultwarden migration (2026-01-07)
- **Documentation:** `SYSTEM.md` Section D (Secrets Management)

---

## Lessons Learned

1. **Always fetch cert from cluster** - Don't trust local copy
2. **Test seal/unseal before commit** - Verify Secret is created
3. **Use strict scope by default** - More secure than cluster-wide
4. **Backup private key monthly** - Recovery impossible without it
5. **Document secret purpose** - Know what needs re-sealing

---

## Verification Checklist

- [ ] SealedSecret exists: `oc get sealedsecret -n <namespace>`
- [ ] Regular Secret created: `oc get secret <secret-name> -n <namespace>`
- [ ] Secret has expected keys: `oc get secret <secret-name> -o yaml`
- [ ] Pod using secret can start: `oc get pods -n <namespace>`
- [ ] No errors in controller logs
- [ ] Public cert in Git matches cluster

---

**Document Version:** 1.0  
**Last Updated:** 2026-01-08  
**Owner:** SRE Team
