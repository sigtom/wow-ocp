---
name: sealed-secrets
description: Create sealed secrets for OpenShift using Bitnami Sealed Secrets. Interactive workflow for securely encrypting secrets with kubeseal before committing to Git.
---

# Sealed Secrets

Interactive tool for creating sealed secrets following the OpenShift homelab security workflow. Never commit raw secrets to Git—always seal them first with kubeseal.

## Prerequisites

- `kubeseal` CLI installed on your system
- `kubectl` or `oc` CLI configured with cluster access
- Public certificate: `pub-sealed-secrets.pem` in the project root

Install kubeseal:
```bash
# macOS
brew install kubeseal

# Linux (download latest release)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.5/kubeseal-0.24.5-linux-amd64.tar.gz
tar -xvzf kubeseal-0.24.5-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/
```

## Usage

### Interactive Mode

Create a sealed secret by answering prompts:

```bash
{baseDir}/scripts/seal-secret.sh
```

The script will prompt for:
1. Secret name
2. Namespace
3. Secret type (Opaque, dockerconfigjson, tls, etc.)
4. Key-value pairs (interactive, enter blank key to finish)

### Quick Secrets (Common Types)

Fast generators for common secret types:

```bash
# Docker Hub credentials
{baseDir}/scripts/quick-secrets.sh docker dockerhub-creds media

# TLS certificate
{baseDir}/scripts/quick-secrets.sh tls my-tls-cert default

# Basic auth (username/password)
{baseDir}/scripts/quick-secrets.sh basicauth admin-creds default

# SSH private key
{baseDir}/scripts/quick-secrets.sh ssh github-key ci-cd

# Secret from file(s)
{baseDir}/scripts/quick-secrets.sh file app-config myapp
```

### Non-Interactive Mode

Pipe a raw secret manifest to seal it:

```bash
cat raw-secret.yaml | {baseDir}/scripts/seal-secret.sh --stdin
```

### Output to File

```bash
{baseDir}/scripts/seal-secret.sh > apps/myapp/overlays/prod/sealed-secret.yaml
```

### Example Workflow

```bash
# Create sealed secret interactively
cd /home/sigtom/wow-ocp
.pi/skills/sealed-secrets/scripts/seal-secret.sh > apps/plex/overlays/prod/plex-claim-sealed.yaml

# Verify the output
cat apps/plex/overlays/prod/plex-claim-sealed.yaml

# Commit to Git (safe - encrypted)
git add apps/plex/overlays/prod/plex-claim-sealed.yaml
git commit -m "Add Plex claim token sealed secret"
git push

# ArgoCD will sync and the sealed-secrets controller will decrypt automatically
```

## Secret Types

Common secret types:
- `Opaque` (default) - Generic key-value pairs
- `kubernetes.io/dockerconfigjson` - Docker registry credentials
- `kubernetes.io/tls` - TLS certificate and key
- `kubernetes.io/basic-auth` - Username and password
- `kubernetes.io/ssh-auth` - SSH private key

## Security Model

1. **Raw Secret Creation**: Script generates a Kubernetes Secret manifest (in memory)
2. **Encryption**: `kubeseal` encrypts with the cluster's public certificate
3. **Sealed Secret**: Output is a SealedSecret CRD (safe to commit)
4. **Deployment**: Sealed Secrets controller decrypts in-cluster only
5. **GitOps**: Commit the SealedSecret to Git, ArgoCD syncs it

## The Prime Directive

**NEVER commit a raw Secret to Git.** Always use this tool to seal secrets before committing.

```yaml
# ❌ BAD - Never commit this
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
data:
  password: cGFzc3dvcmQxMjM=  # Base64 is NOT encryption

# ✅ GOOD - Commit this instead
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret
spec:
  encryptedData:
    password: AgBg7... # Encrypted with cluster public key
```

## Troubleshooting

**Error: "cannot fetch certificate"**
- Ensure kubeseal can reach the cluster: `oc whoami`
- Or use the offline cert: `--cert pub-sealed-secrets.pem`

**Error: "pub-sealed-secrets.pem not found"**
- Run from project root: `/home/sigtom/wow-ocp`
- Or specify cert path: `--cert /path/to/pub-sealed-secrets.pem`

**Secret not decrypting in cluster**
- Verify sealed-secrets controller is running:
  ```bash
  oc get pods -n kube-system -l name=sealed-secrets-controller
  ```
- Check controller logs:
  ```bash
  oc logs -n kube-system -l name=sealed-secrets-controller
  ```

## When to Use

- Creating secrets for apps before deploying to OpenShift
- Rotating credentials (create new sealed secret, replace old one)
- Adding secrets to GitOps repo (ArgoCD/Kustomize workflow)
- Any time you need to store sensitive data in Git safely
