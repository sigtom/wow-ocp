# Runbook 007: Pod CrashLoopBackOff Troubleshooting

**Frequency:** Common (new deployments, config changes, resource exhaustion)
**Impact:** High - Application unavailable
**Last Occurred:** Ongoing (routine operations)
**MTTR:** 10-45 minutes

---

## Symptoms

- Pod status shows `CrashLoopBackOff`
- Restart count incrementing continuously
- Application unavailable/unreachable
- Pod exists but not responding to requests

**Quick Check:**
```bash
# Check pod status
oc get pods -n <namespace>

# Check recent logs
oc logs <pod-name> -n <namespace> --tail=50

# Check previous crash logs
oc logs <pod-name> -n <namespace> --previous
```

---

## Root Cause Analysis

### Common Causes (Priority Order)

1. **Application Error / Crash** (35% of cases)
   - Missing environment variable
   - Configuration file error
   - Database connection failure
   - Application bug

2. **Resource Limits (OOMKilled)** (25% of cases)
   - Memory limit too low
   - Memory leak in application
   - CPU throttling causing timeouts

3. **Liveness Probe Failure** (15% of cases)
   - Probe checking wrong port/path
   - Application slow to start (timeout too short)
   - Probe running before app is ready

4. **Dependency Not Available** (10% of cases)
   - Database/service not running
   - Secret/ConfigMap missing
   - Volume mount failed

5. **Permission Issues** (10% of cases)
   - Cannot write to filesystem
   - User/group mismatch with volume
   - SELinux blocking access

6. **Container Image Issues** (5% of cases)
   - Wrong architecture (amd64 vs arm64)
   - Image pull failure
   - Corrupted image

---

## Diagnosis Steps

### Step 1: Check Pod Status and Events
```bash
oc describe pod <pod-name> -n <namespace>
```

**Look for Events section:**
```
Events:
  Type     Reason     Message
  ----     ------     -------
  Normal   Pulled     Container image pulled
  Normal   Created    Created container
  Normal   Started    Started container
  Warning  BackOff    Back-off restarting failed container
```

**Key Event Messages:**

| Message | Cause |
|---------|-------|
| `OOMKilled` | Memory limit exceeded |
| `exec format error` | Wrong CPU architecture |
| `CreateContainerConfigError` | ConfigMap/Secret missing |
| `CrashLoopBackOff` | Container exits with error code |
| `Error: failed to start container` | Image or entrypoint problem |

### Step 2: Check Current Logs
```bash
oc logs <pod-name> -n <namespace> --tail=100
```

**Common Log Patterns:**

| Pattern | Probable Cause |
|---------|----------------|
| `panic: runtime error` | Application bug |
| `FATAL: password authentication failed` | Wrong DB credentials |
| `Error: ENOENT: no such file or directory` | Missing file/mount |
| `dial tcp: connection refused` | Service dependency down |
| `signal: killed` | OOMKilled by kernel |
| Empty output | Container exits immediately (check previous logs) |

### Step 3: Check Previous Container Logs
```bash
# Shows logs from the crashed container
oc logs <pod-name> -n <namespace> --previous
```

**Critical for:** Understanding what happened before the crash.

### Step 4: Check Resource Usage
```bash
# Check current resource usage
oc adm top pod <pod-name> -n <namespace>

# Check limits/requests
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].resources}'
```

**Example Output:**
```json
{
  "limits": {
    "cpu": "500m",
    "memory": "512Mi"
  },
  "requests": {
    "cpu": "100m",
    "memory": "128Mi"
  }
}
```

**Problem Indicators:**
- Memory usage near/at limit = likely OOM
- No limits defined = resource bomb risk

### Step 5: Check Liveness/Readiness Probes
```bash
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].livenessProbe}'
```

**Example:**
```json
{
  "httpGet": {
    "path": "/health",
    "port": 8080,
    "scheme": "HTTP"
  },
  "initialDelaySeconds": 30,
  "periodSeconds": 10,
  "timeoutSeconds": 5
}
```

**Problem Patterns:**
- `initialDelaySeconds` too short (app not ready yet)
- Wrong `port` (app listening on different port)
- Wrong `path` (endpoint doesn't exist)

### Step 6: Check Volume Mounts
```bash
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.volumes}'
```

**Verify:**
- PVCs are `Bound`
- ConfigMaps/Secrets exist
- Mount paths don't conflict

---

## Resolution by Root Cause

### Fix 1: OOMKilled (Memory Limit Too Low)

**Symptom:**
- Events show: `OOMKilled`
- Logs show: `signal: killed` or abrupt cutoff

**Resolution:**

1. **Check historical memory usage:**
```bash
# If metrics available
oc adm top pod <pod-name> -n <namespace> --containers
```

2. **Increase memory limits:**

**File:** `apps/<app-name>/base/deployment.yaml`

```yaml
containers:
  - name: <app-name>
    resources:
      requests:
        memory: "512Mi"  # Increased from 128Mi
        cpu: "100m"
      limits:
        memory: "2Gi"    # Increased from 512Mi
        cpu: "1000m"
```

3. **Apply via GitOps:**
```bash
git add apps/<app-name>/base/deployment.yaml
git commit -m "fix: increase memory limits for <app-name> to prevent OOM"
git push origin main

argocd app sync <app-name>
```

4. **Monitor:**
```bash
watch oc get pods -n <namespace>
# Wait for pod to stabilize (restart count stops increasing)
```

### Fix 2: Missing Environment Variable or Secret

**Symptom:**
- Logs show: `FATAL: environment variable X is not set`
- Events show: `CreateContainerConfigError`

**Resolution:**

1. **Verify secret/configmap exists:**
```bash
oc get secret <secret-name> -n <namespace>
oc get configmap <configmap-name> -n <namespace>
```

2. **If missing, create sealed secret:**
```bash
# Create raw secret
oc create secret generic <secret-name> \
  --from-literal=DB_PASSWORD=<password> \
  --dry-run=client -o yaml > /tmp/secret.yaml

# Seal it
kubeseal --cert pub-sealed-secrets.pem \
  --format yaml < /tmp/secret.yaml \
  > apps/<app-name>/base/<secret-name>-sealed-secret.yaml

# Cleanup
rm /tmp/secret.yaml

# Commit
git add apps/<app-name>/base/<secret-name>-sealed-secret.yaml
git commit -m "fix: add missing secret for <app-name>"
git push origin main

argocd app sync <app-name>
```

3. **Verify mount in deployment:**
```yaml
spec:
  containers:
    - name: <app-name>
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: <secret-name>
              key: DB_PASSWORD
```

### Fix 3: Liveness Probe Killing Healthy Container

**Symptom:**
- Logs show app is working
- Pod restarts every X seconds (probe period)
- No errors in logs before restart

**Resolution:**

1. **Test probe manually:**
```bash
# For HTTP probe
oc exec <pod-name> -n <namespace> -- curl -f http://localhost:8080/health

# For TCP probe
oc exec <pod-name> -n <namespace> -- nc -zv localhost 8080

# For exec probe
oc exec <pod-name> -n <namespace> -- /bin/sh -c "<probe-command>"
```

2. **Adjust probe timing:**

**File:** `apps/<app-name>/base/deployment.yaml`

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 60  # Increased from 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3       # Allow 3 failures before restart
```

3. **Or remove liveness probe temporarily to confirm:**
```yaml
# Comment out livenessProbe section
# livenessProbe:
#   httpGet:
#     path: /health
#     port: 8080
```

**⚠️ WARNING:** Remove only for testing. Production apps MUST have probes.

### Fix 4: Application Waiting for Dependency (Database/Service)

**Symptom:**
- Logs show: `connection refused` or `host not found`
- App tries to connect to service that's not ready

**Resolution (Option A: Use InitContainer):**

```yaml
spec:
  initContainers:
    - name: wait-for-db
      image: busybox:latest
      command:
        - sh
        - -c
        - |
          until nc -zv postgres-service 5432; do
            echo "Waiting for postgres..."
            sleep 5
          done
          echo "Postgres is ready"
  containers:
    - name: <app-name>
      # Main app starts after initContainer succeeds
```

**Resolution (Option B: Add Retry Logic in App):**

If app doesn't have built-in retries, add startup wrapper:

```yaml
command:
  - /bin/sh
  - -c
  - |
    for i in $(seq 1 30); do
      if /app/healthcheck; then
        exec /app/start
      fi
      echo "Waiting for dependencies... ($i/30)"
      sleep 10
    done
    echo "Failed to start after 5 minutes"
    exit 1
```

### Fix 5: Permission Denied (Filesystem)

**Symptom:**
- Logs show: `Permission denied` when writing files
- Events show: `Error: failed to create file`

**Resolution:**

1. **Check pod security context:**
```bash
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.securityContext}'
```

2. **Add fsGroup to match volume permissions:**

```yaml
spec:
  securityContext:
    runAsUser: 1000      # Non-root user
    runAsGroup: 1000
    fsGroup: 1000         # Sets group ownership of volumes
    fsGroupChangePolicy: "OnRootMismatch"  # Faster than Always
  containers:
    - name: <app-name>
      securityContext:
        runAsNonRoot: true
        allowPrivilegeEscalation: false
```

3. **For NFS volumes with root_squash:**

If TrueNAS has `root_squash` enabled, root user (UID 0) is mapped to `nobody`.

**Fix:**
```yaml
securityContext:
  runAsUser: 1001  # Use non-root UID
  fsGroup: 1001
```

### Fix 6: Wrong Container Image Architecture

**Symptom:**
- Error: `exec format error`
- Cluster is x86_64 but image is arm64

**Resolution:**

1. **Verify image architecture:**
```bash
docker manifest inspect <image>:<tag> | grep architecture
```

2. **Use multi-arch image or specify platform:**

**Bad:**
```yaml
image: myapp:latest  # May be wrong architecture
```

**Good:**
```yaml
image: myapp:latest-amd64  # Explicit architecture
# OR
image: myapp:latest@sha256:abc123...  # Pin by digest
```

---

## Prevention

### 1. Always Define Resource Limits

**Bad:**
```yaml
containers:
  - name: myapp
    # No resources defined = cluster bomb
```

**Good:**
```yaml
containers:
  - name: myapp
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "1000m"
        memory: "1Gi"
```

### 2. Use Startup Probes for Slow Apps

**For apps that take >30s to start:**

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 10
  failureThreshold: 30  # 30 * 10s = 5 minutes max startup time

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Benefits:**
- Startup probe allows slow initialization
- Liveness probe only runs after startup succeeds

### 3. Test Locally Before Deploying

```bash
# Test image locally
docker run --rm <image>:<tag>

# Test with resource limits
docker run --rm --memory=512m --cpus=0.5 <image>:<tag>

# Test with env vars
docker run --rm -e DB_HOST=test <image>:<tag>
```

### 4. Use Readiness Probe to Control Traffic

**Pattern:** Liveness = "is app alive?", Readiness = "is app ready for traffic?"

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
```

---

## Troubleshooting Decision Tree

```
Pod CrashLoopBackOff
    │
    ├─ Events show "OOMKilled"?
    │   └─ Yes → Increase memory limits (Fix 1)
    │
    ├─ Logs show "Permission denied"?
    │   └─ Yes → Fix fsGroup/runAsUser (Fix 5)
    │
    ├─ Logs show "connection refused"?
    │   └─ Yes → Check dependency health (Fix 4)
    │
    ├─ Logs show "environment variable not set"?
    │   └─ Yes → Check secret/configmap (Fix 2)
    │
    ├─ Logs empty or exits immediately?
    │   └─ Yes → Check previous logs: oc logs --previous
    │
    ├─ Events show "exec format error"?
    │   └─ Yes → Wrong image architecture (Fix 6)
    │
    └─ Pod restarts every X seconds?
        └─ Yes → Liveness probe too aggressive (Fix 3)
```

---

## Common Application-Specific Issues

### PostgreSQL
```
initdb: error: directory "/var/lib/postgresql/data" exists but is not empty
```
**Fix:** Empty directory or use subdirectory:
```yaml
env:
  - name: PGDATA
    value: /var/lib/postgresql/data/pgdata
```

### Redis
```
Can't open the append-only file: Permission denied
```
**Fix:** Add `fsGroup`:
```yaml
securityContext:
  fsGroup: 999  # Redis UID
```

### Nginx
```
nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)
```
**Fix:** Use non-privileged port:
```yaml
env:
  - name: NGINX_PORT
    value: "8080"
```

---

## Related Issues

- **Issue:** NFD Garbage Collector crash (2025-12-21)
- **Issue:** Prometheus crash from storage exhaustion (2025-12-31)
- **Documentation:** Resource limits in `SYSTEM.md`

---

## Lessons Learned

1. **Check `--previous` logs first** - Shows what caused the crash
2. **OOMKilled is silent** - Only visible in Events, not logs
3. **Liveness != Readiness** - Use separate probes with different timing
4. **Resource limits prevent cluster-wide impact** - Always define them
5. **Test probe endpoints manually** - Don't guess, verify they work

---

## Verification Checklist

- [ ] Pod shows `Running` status
- [ ] Restart count stops increasing
- [ ] `oc logs` shows normal application output
- [ ] Liveness probe passing: `oc describe pod` shows no probe failures
- [ ] Resource usage within limits: `oc adm top pod`
- [ ] Application responds to requests (test endpoint)
- [ ] No error events in last 5 minutes

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Owner:** SRE Team
