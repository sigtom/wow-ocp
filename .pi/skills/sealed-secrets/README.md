# Sealed Secrets Skill

Production-ready tool for creating sealed secrets in your OpenShift homelab.

## Quick Start

```bash
# Interactive mode
./scripts/seal-secret.sh > apps/myapp/overlays/prod/sealed-secret.yaml

# Pipe mode
cat raw-secret.yaml | ./scripts/seal-secret.sh --stdin > sealed-secret.yaml
```

## Features

- ✅ Interactive prompts for secret name, namespace, type, and key-value pairs
- ✅ Password masking for sensitive input
- ✅ Validation of Kubernetes naming conventions
- ✅ Support for multiple secret types (Opaque, dockerconfigjson, TLS, etc.)
- ✅ Automatic discovery of pub-sealed-secrets.pem in project root
- ✅ Preflight checks (kubeseal, kubectl/oc, certificate)
- ✅ Error handling with colored output
- ✅ Stdin mode for piping existing secrets
- ✅ Safe for Git commits (encrypted output only)

## The Workflow

1. **Create**: Run the script to generate a sealed secret
2. **Output**: Redirect to file in your GitOps repo
3. **Commit**: Push to Git (safe - it's encrypted)
4. **Deploy**: ArgoCD syncs, sealed-secrets controller decrypts in-cluster

## Example Session

```bash
$ ./scripts/seal-secret.sh
INFO: Preflight checks passed ✓
INFO: === Sealed Secret Creator ===

Secret name: plex-claim
Namespace: media
Secret type:
  1) Opaque (default - generic key-value)
  2) kubernetes.io/dockerconfigjson (Docker registry)
  3) kubernetes.io/tls (TLS cert/key)
  4) kubernetes.io/basic-auth (username/password)
  5) kubernetes.io/ssh-auth (SSH private key)
Select type [1]: 1

Enter key-value pairs (press Enter with blank key to finish):
Key (or blank to finish): PLEX_CLAIM
Value for 'PLEX_CLAIM': ****
Key (or blank to finish): 

INFO: Creating secret with 1 key(s)...
INFO: Sealing secret with kubeseal...
SUCCESS: Sealed secret created successfully! Safe to commit to Git.
```

## Documentation

See [SKILL.md](SKILL.md) for full documentation.
