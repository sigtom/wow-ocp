# Sealed Secrets - Quick Start

## Installation Check

```bash
# Verify prerequisites
which kubeseal && which oc && ls pub-sealed-secrets.pem
```

If any are missing:
- **kubeseal**: `brew install kubeseal` (macOS) or download from [releases](https://github.com/bitnami-labs/sealed-secrets/releases)
- **oc**: Install OpenShift CLI from [Red Hat](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/)
- **pub-sealed-secrets.pem**: Fetch from cluster: `kubeseal --fetch-cert > pub-sealed-secrets.pem`

## 30-Second Workflow

```bash
# 1. Create sealed secret (interactive)
.pi/skills/sealed-secrets/scripts/seal-secret.sh > apps/myapp/overlays/prod/sealed-secret.yaml

# 2. Commit to Git (safe - it's encrypted!)
git add apps/myapp/overlays/prod/sealed-secret.yaml
git commit -m "Add sealed secret for myapp"
git push

# 3. ArgoCD syncs, sealed-secrets controller decrypts in-cluster
# Done! ✅
```

## Common Scenarios

### Scenario 1: Docker Hub Credentials

```bash
.pi/skills/sealed-secrets/scripts/quick-secrets.sh docker dockerhub-creds default > dockerhub-sealed.yaml
```

### Scenario 2: API Key for Plex

```bash
.pi/skills/sealed-secrets/scripts/seal-secret.sh
# Enter:
#   Name: plex-claim
#   Namespace: media
#   Type: 1 (Opaque)
#   Key: PLEX_CLAIM
#   Value: <paste your claim token>
```

### Scenario 3: Existing Secret YAML

```bash
# You already have a secret.yaml (DON'T COMMIT IT!)
cat secret.yaml | .pi/skills/sealed-secrets/scripts/seal-secret.sh --stdin > sealed-secret.yaml
rm secret.yaml  # Delete the raw secret!
git add sealed-secret.yaml
```

### Scenario 4: TLS Certificate

```bash
.pi/skills/sealed-secrets/scripts/quick-secrets.sh tls myapp-tls myapp > myapp-tls-sealed.yaml
# Prompts for cert and key file paths
```

## Verification

After ArgoCD syncs, verify in-cluster:

```bash
# Check if SealedSecret exists
oc get sealedsecrets -n <namespace>

# Check if Secret was created (decrypted by controller)
oc get secrets -n <namespace>

# View secret data (base64 encoded, not the sealed version)
oc get secret <name> -n <namespace> -o yaml
```

## Troubleshooting

### "cannot fetch certificate"
```bash
# Use offline cert
.pi/skills/sealed-secrets/scripts/seal-secret.sh --cert pub-sealed-secrets.pem
```

### "Secret not decrypting"
```bash
# Check sealed-secrets controller
oc get pods -n kube-system -l name=sealed-secrets-controller
oc logs -n kube-system -l name=sealed-secrets-controller --tail=50
```

### "Invalid name"
Kubernetes names must:
- Be lowercase
- Start/end with alphanumeric
- Contain only alphanumeric and hyphens
- Max 253 characters

## Remember

🔒 **NEVER commit raw Secrets to Git**  
✅ **ALWAYS seal them first**  
🚀 **Let ArgoCD and sealed-secrets controller do the rest**

For full documentation, see [SKILL.md](SKILL.md)
