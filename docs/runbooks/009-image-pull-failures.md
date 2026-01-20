# Runbook 009: Image Pull Failures (ImagePullBackOff / ErrImagePull)

**Frequency:** Common (new deployments, Docker Hub rate limits)
**Impact:** High - Pod cannot start
**Last Occurred:** Ongoing (Docker Hub rate limiting)
**MTTR:** 5-20 minutes

---

## Symptoms

- Pod status shows `ImagePullBackOff` or `ErrImagePull`
- Events show: `Failed to pull image` or `manifest unknown`
- Pod stuck in `Pending` state with image pull errors

**Quick Check:**
```bash
# Check pod status
oc get pods -n <namespace>

# Check events
oc describe pod <pod-name> -n <namespace> | grep -A 10 Events
```

---

## Root Cause Analysis

### Common Causes (Priority Order)

1. **Docker Hub Rate Limit Exceeded** (45% of cases)
   - Anonymous pulls: 100 per 6 hours
   - Free account: 200 per 6 hours
   - Cluster hitting limit quickly

2. **Image Does Not Exist** (25% of cases)
   - Typo in image name or tag
   - Image deleted from registry
   - Private image without credentials

3. **Registry Authentication Failed** (15% of cases)
   - Pull secret missing or wrong
   - Token expired
   - Wrong registry URL

4. **Network Issues** (10% of cases)
   - Cannot reach registry (firewall, DNS)
   - SSL/TLS certificate errors
   - Proxy misconfiguration

5. **Wrong Architecture** (5% of cases)
   - Image built for arm64, cluster is amd64
   - Multi-arch manifest missing

---

## Diagnosis Steps

### Step 1: Check Pod Events
```bash
oc describe pod <pod-name> -n <namespace>
```

**Look for Image Pull Events:**
```
Events:
  Type     Reason          Message
  ----     ------          -------
  Normal   Pulling         Pulling image "docker.io/library/nginx:latest"
  Warning  Failed          Failed to pull image: toomanyrequests: rate limit exceeded
  Warning  Failed          Error: ErrImagePull
  Normal   BackOff         Back-off pulling image "docker.io/library/nginx:latest"
  Warning  Failed          Error: ImagePullBackOff
```

**Common Error Messages:**

| Message | Cause |
|---------|-------|
| `toomanyrequests: rate limit exceeded` | Docker Hub rate limit |
| `manifest unknown` | Image/tag does not exist |
| `unauthorized: authentication required` | Missing/wrong pull secret |
| `error pulling image configuration` | Network/registry issue |
| `x509: certificate signed by unknown authority` | SSL cert problem |

### Step 2: Check Image Name and Tag
```bash
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].image}'
```

**Common Mistakes:**
- `nginx:lastest` (typo: should be `latest`)
- `docker.io/nginx` (missing tag, defaults to `latest`)
- `ghcr.io/user/app:v1.2.3` (private repo, needs auth)

### Step 3: Test Image Pull Manually
```bash
# On any node
oc debug node/<node-name>
chroot /host

# Try pulling with podman/crictl
podman pull docker.io/library/nginx:latest

# OR
crictl pull docker.io/library/nginx:latest
```

**Expected:** Image pulls successfully
**Problem:** Same error as pod (confirms cluster-wide issue)

### Step 4: Check Pull Secret (If Private Registry)
```bash
# Check if pull secret exists
oc get secret -n <namespace> | grep pull

# For global pull secret
oc get secret pull-secret -n openshift-config -o yaml
```

### Step 5: Check Rate Limit Status (Docker Hub)

**Anonymous (no auth):**
```bash
TOKEN=$(curl "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
curl --head -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>&1 | grep -i rate
```

**Expected Output:**
```
ratelimit-limit: 100;w=21600
ratelimit-remaining: 95;w=21600
```

**Problem (Limit Hit):**
```
ratelimit-remaining: 0;w=21600
```

---

## Resolution by Root Cause

### Fix 1: Docker Hub Rate Limit Exceeded

**Symptom:**
- Error: `toomanyrequests: rate limit exceeded`
- Multiple pods failing across cluster
- Rate limit header shows `ratelimit-remaining: 0`

**Resolution (Option A: Add Docker Hub Credentials to Global Pull Secret):**

**RECOMMENDED APPROACH - Fixes all future pulls cluster-wide**

1. **Create Docker Hub access token:**
   - Go to: https://hub.docker.com/settings/security
   - Click "New Access Token"
   - Description: "OpenShift Cluster Pull Secret"
   - Permissions: "Read-only"
   - Copy token

2. **Create local docker config:**
```bash
# Login locally to generate config
docker login docker.io -u <your-username>
# Enter the access token as password

# Config is saved to ~/.docker/config.json
cat ~/.docker/config.json
```

**Output:**
```json
{
  "auths": {
    "docker.io": {
      "auth": "BASE64_ENCODED_USERNAME:TOKEN"
    }
  }
}
```

3. **Update OpenShift global pull secret:**
```bash
# Get current pull secret
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/pull-secret.json

# Merge with your Docker Hub credentials
jq -s '.[0] * .[1]' /tmp/pull-secret.json ~/.docker/config.json > /tmp/merged-pull-secret.json

# Update cluster pull secret
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/tmp/merged-pull-secret.json

# Cleanup
rm /tmp/pull-secret.json /tmp/merged-pull-secret.json
```

4. **Wait for nodes to pick up new secret (5-10 minutes) OR restart nodes:**
```bash
# Restart nodes to apply immediately
oc adm drain <node-name> --ignore-daemonsets --delete-emptydir-data
oc adm uncordon <node-name>
```

5. **Verify rate limit increased:**
```bash
# Should now show 200 pulls per 6 hours (free tier)
TOKEN=$(curl "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" -u <username>:<token> | jq -r .token)
curl --head -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>&1 | grep -i rate
```

**Resolution (Option B: Use Alternative Registry):**

If you control the image, mirror it to a different registry:

```bash
# Mirror to Quay.io
podman pull docker.io/library/nginx:latest
podman tag docker.io/library/nginx:latest quay.io/<your-username>/nginx:latest
podman push quay.io/<your-username>/nginx:latest

# Update deployment
image: quay.io/<your-username>/nginx:latest
```

### Fix 2: Image Does Not Exist

**Symptom:**
- Error: `manifest unknown` or `not found`
- Single pod failing, others OK

**Resolution:**

1. **Verify image exists:**
```bash
# For Docker Hub
curl -s https://hub.docker.com/v2/repositories/library/nginx/tags | jq -r '.results[].name' | head -n 10

# For Quay.io
curl -s https://quay.io/api/v1/repository/<org>/<repo>/tag/ | jq -r '.tags[].name' | head -n 10
```

2. **Check for typos:**
```yaml
# Common mistakes
image: nginx:lastest  # WRONG
image: nginx:latest   # CORRECT

image: my-app  # WRONG - missing registry and tag
image: quay.io/myorg/my-app:v1.0.0  # CORRECT
```

3. **Update deployment:**
```bash
git add apps/<app-name>/base/deployment.yaml
git commit -m "fix: correct image tag for <app-name>"
git push origin main

argocd app sync <app-name>
```

### Fix 3: Registry Authentication Failed (Private Image)

**Symptom:**
- Error: `unauthorized: authentication required`
- Image is on private registry (ghcr.io, quay.io private repo)

**Resolution:**

1. **Create registry credentials:**
```bash
# For GitHub Container Registry (ghcr.io)
docker login ghcr.io -u <github-username>
# Use Personal Access Token as password (with read:packages scope)

# For Quay.io
docker login quay.io -u <quay-username>
# Use Robot Token or password
```

2. **Create pull secret in namespace:**
```bash
# Create raw secret from docker config
oc create secret generic <registry-name>-pull-secret \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson \
  --dry-run=client -o yaml > /tmp/pull-secret.yaml

# Seal it
kubeseal --cert pub-sealed-secrets.pem \
  --format yaml < /tmp/pull-secret.yaml \
  > apps/<app-name>/base/<registry-name>-pull-secret-sealed.yaml

# Cleanup
rm /tmp/pull-secret.yaml
```

3. **Reference in deployment:**
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: <registry-name>-pull-secret-sealed
      containers:
        - name: <app-name>
          image: ghcr.io/<org>/<repo>:tag
```

4. **Commit and sync:**
```bash
git add apps/<app-name>/base/
git commit -m "feat: add pull secret for private registry"
git push origin main

argocd app sync <app-name>
```

### Fix 4: Network Issues (Cannot Reach Registry)

**Symptom:**
- Error: `error pulling image configuration: Get https://...: dial tcp: i/o timeout`
- Intermittent failures

**Resolution:**

1. **Test connectivity from node:**
```bash
oc debug node/<node-name>
chroot /host

# Test DNS
nslookup docker.io
nslookup registry-1.docker.io

# Test HTTPS
curl -I https://registry-1.docker.io/v2/
# Should return: HTTP/2 401 (unauthorized is OK, means we reached it)
```

2. **If DNS fails:**
```bash
# Check node DNS config
cat /etc/resolv.conf

# Test against known good DNS
nslookup docker.io 8.8.8.8
```

**Fix:** Update DNS configuration or fix upstream DNS.

3. **If HTTPS fails with certificate error:**
```bash
# Check certificate
openssl s_client -connect registry-1.docker.io:443 -servername registry-1.docker.io
```

**Fix:** Update system CA certificates or configure custom CA bundle.

### Fix 5: Wrong Architecture (amd64 vs arm64)

**Symptom:**
- Image pulls successfully
- Pod crashes immediately with: `exec format error`

**Resolution:**

1. **Check image manifest:**
```bash
docker manifest inspect docker.io/library/nginx:latest | jq '.manifests[].platform'
```

**Expected (Multi-arch):**
```json
{"architecture": "amd64", "os": "linux"}
{"architecture": "arm64", "os": "linux"}
```

**Problem (Single arch):**
```json
{"architecture": "arm64", "os": "linux"}
# Missing amd64!
```

2. **Use multi-arch image or specify platform:**
```yaml
# Option 1: Find multi-arch variant
image: nginx:latest  # Usually multi-arch

# Option 2: Specify exact platform
image: nginx:latest-amd64

# Option 3: Use digest (pins specific arch)
image: nginx@sha256:abc123...
```

---

## Prevention

### 1. Always Configure Docker Hub Authentication

**One-time setup (DO THIS NOW):**

```bash
# Update global pull secret with Docker Hub credentials
# See Fix 1 for detailed steps

# Benefit: Increases rate limit from 100 to 200 pulls per 6 hours
```

### 2. Use Image Digest Pinning (Critical Apps)

**Bad (tag can change):**
```yaml
image: nginx:latest
```

**Good (immutable digest):**
```yaml
image: nginx@sha256:4c0fdaa8b6341bfdeca5f18f7837462c80cff90527ee35ef185571e1c327afac
```

**How to get digest:**
```bash
docker pull nginx:latest
docker inspect nginx:latest | jq -r '.[0].RepoDigests[0]'
```

### 3. Mirror Critical Images to Private Registry

**For production apps:**

1. Push to internal registry (e.g., OpenShift internal registry)
2. Update deployments to use internal image

**Example:**
```bash
# Tag and push to OpenShift registry
oc registry info  # Get registry URL
podman tag nginx:latest default-route-openshift-image-registry.apps.ossus.sigtomtech.com/<namespace>/nginx:latest
podman push default-route-openshift-image-registry.apps.ossus.sigtomtech.com/<namespace>/nginx:latest

# Use in deployment
image: image-registry.openshift-image-registry.svc:5000/<namespace>/nginx:latest
```

### 4. Monitor Rate Limit Usage

**Script:** `scripts/check-dockerhub-rate-limit.sh`

```bash
#!/bin/bash
set -e

echo "Checking Docker Hub rate limit..."

# Get credentials from pull secret
DOCKERHUB_AUTH=$(oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths["docker.io"].auth' | base64 -d)
USERNAME=$(echo $DOCKERHUB_AUTH | cut -d: -f1)
TOKEN=$(echo $DOCKERHUB_AUTH | cut -d: -f2)

# Get token
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" -u "$USERNAME:$TOKEN" | jq -r .token)

# Check rate limit
HEADERS=$(curl -s --head -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>&1)

LIMIT=$(echo "$HEADERS" | grep -i "ratelimit-limit:" | awk '{print $2}' | tr -d '\r')
REMAINING=$(echo "$HEADERS" | grep -i "ratelimit-remaining:" | awk '{print $2}' | tr -d '\r')

echo "Rate Limit: $LIMIT pulls per 6 hours"
echo "Remaining: $REMAINING pulls"

if [ "${REMAINING%%/*}" -lt 20 ]; then
  echo "WARNING: Low remaining pulls!"
  exit 1
fi

echo "✓ Rate limit OK"
```

**Run daily:**
```bash
./scripts/check-dockerhub-rate-limit.sh
```

---

## Troubleshooting Decision Tree

```
ImagePullBackOff
    │
    ├─ Error: "rate limit exceeded"?
    │   └─ Yes → Add Docker Hub credentials (Fix 1)
    │
    ├─ Error: "manifest unknown"?
    │   └─ Yes → Check image name/tag exists (Fix 2)
    │
    ├─ Error: "unauthorized"?
    │   └─ Yes → Add pull secret (Fix 3)
    │
    ├─ Error: "dial tcp timeout"?
    │   └─ Yes → Check network/DNS (Fix 4)
    │
    └─ Pod crashes with "exec format error"?
        └─ Yes → Wrong architecture (Fix 5)
```

---

## Common Registries and Authentication

### Docker Hub (docker.io)
- **Auth:** Personal Access Token (read-only)
- **Rate Limit:** 100 anonymous, 200 authenticated
- **Pull Secret:** Global (`pull-secret` in `openshift-config`)

### GitHub Container Registry (ghcr.io)
- **Auth:** Personal Access Token (scope: `read:packages`)
- **Rate Limit:** None (for public images with auth)
- **Pull Secret:** Per-namespace

### Quay.io (quay.io)
- **Auth:** Robot Account or username/password
- **Rate Limit:** None for public, per-plan for private
- **Pull Secret:** Per-namespace or global

### OpenShift Internal Registry
- **Auth:** Service Account token (automatic)
- **URL:** `image-registry.openshift-image-registry.svc:5000`
- **Pull Secret:** None needed (same cluster)

---

## Related Issues

- **Issue:** Docker Hub "Docker Tax" (2025 rate limit changes)
- **Documentation:** `SYSTEM.md` Section H (Image Management)

---

## Lessons Learned

1. **Always authenticate to Docker Hub** - Even public images have rate limits
2. **Use global pull secret** - Avoids per-namespace secret management
3. **Pin critical images by digest** - Tags can change/disappear
4. **Test pulls on fresh node** - Cached images hide rate limit issues
5. **Monitor rate limit usage** - Don't wait for production failure

---

## Verification Checklist

- [ ] Pod transitions from `ImagePullBackOff` to `Running`
- [ ] No `Failed to pull image` events in pod description
- [ ] Image pull completes in <30 seconds (check with `oc get events`)
- [ ] Rate limit shows >50 remaining pulls: `scripts/check-dockerhub-rate-limit.sh`
- [ ] All nodes can reach registry: test from each node

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Owner:** SRE Team
