#!/bin/bash
# Example usage scenarios for seal-secret.sh

# Example 1: Create a sealed secret interactively (will prompt for inputs)
echo "=== Example 1: Interactive Mode ==="
echo "Run: .pi/skills/sealed-secrets/scripts/seal-secret.sh"
echo "Then answer the prompts for secret name, namespace, type, and key-value pairs"
echo ""

# Example 2: Pipe an existing raw secret (DO NOT COMMIT raw-secret.yaml!)
echo "=== Example 2: Pipe Mode ==="
cat > /tmp/raw-secret-example.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: plex-claim
  namespace: media
type: Opaque
stringData:
  PLEX_CLAIM: claim-xxxxxxxxxxxxxxxxxxxx
EOF

echo "Created example raw secret in /tmp/raw-secret-example.yaml"
echo "Run: cat /tmp/raw-secret-example.yaml | .pi/skills/sealed-secrets/scripts/seal-secret.sh --stdin"
echo ""

# Example 3: Docker registry secret
echo "=== Example 3: Docker Registry Secret ==="
cat > /tmp/docker-secret-example.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: dockerhub-creds
  namespace: default
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "https://index.docker.io/v1/": {
          "username": "myusername",
          "password": "mypassword",
          "email": "myemail@example.com",
          "auth": "bXl1c2VybmFtZTpteXBhc3N3b3Jk"
        }
      }
    }
EOF

echo "Created Docker secret example in /tmp/docker-secret-example.yaml"
echo "Run: cat /tmp/docker-secret-example.yaml | .pi/skills/sealed-secrets/scripts/seal-secret.sh --stdin > dockerhub-sealed.yaml"
echo ""

# Example 4: TLS Certificate Secret
echo "=== Example 4: TLS Certificate Secret ==="
echo "For TLS secrets, you typically have tls.crt and tls.key files:"
echo ""
echo "kubectl create secret tls my-tls-secret \\"
echo "  --cert=path/to/tls.crt \\"
echo "  --key=path/to/tls.key \\"
echo "  --dry-run=client -o yaml | \\"
echo "  .pi/skills/sealed-secrets/scripts/seal-secret.sh --stdin > my-tls-sealed.yaml"
echo ""

# Example 5: Basic Auth Secret
echo "=== Example 5: Basic Auth Secret ==="
echo "kubectl create secret generic basic-auth \\"
echo "  --from-literal=username=admin \\"
echo "  --from-literal=password=secret123 \\"
echo "  --dry-run=client -o yaml | \\"
echo "  .pi/skills/sealed-secrets/scripts/seal-secret.sh --stdin > basic-auth-sealed.yaml"
echo ""

# Example 6: GitOps Workflow
echo "=== Example 6: Complete GitOps Workflow ==="
echo "# 1. Create sealed secret"
echo ".pi/skills/sealed-secrets/scripts/seal-secret.sh > apps/myapp/overlays/prod/sealed-secret.yaml"
echo ""
echo "# 2. Add to kustomization.yaml"
echo "cd apps/myapp/overlays/prod"
echo "kustomize edit add resource sealed-secret.yaml"
echo ""
echo "# 3. Commit to Git"
echo "git add apps/myapp/overlays/prod/"
echo "git commit -m 'Add sealed secret for myapp'"
echo "git push"
echo ""
echo "# 4. ArgoCD will sync automatically and sealed-secrets controller will decrypt in-cluster"
echo ""

# Cleanup message
echo "=== Note ==="
echo "The example files in /tmp are for demonstration only."
echo "NEVER commit raw secrets to Git - always seal them first!"
echo ""
echo "Clean up examples with: rm /tmp/*-example.yaml"
