# Runbook 003: FUSE Mount Propagation Failure (Media Apps)

**Frequency:** Common (when deploying new media apps or changing nodes)
**Impact:** High - Media apps cannot access cloud content
**Last Occurred:** 2025-12-31 (resolved with Sidecar Pattern)
**MTTR:** 10-15 minutes (if sidecar pattern is used)

---

## Symptoms

- Media apps (Sonarr/Radarr/Plex) show empty directories for `/mnt/media`
- Logs show: `No such file or directory` when accessing media paths
- Rclone sidecars are running and healthy
- Standalone rclone mount pods exist but apps can't see mounts
- Apps work on one node but fail when moved to another node

**Quick Check:**
```bash
# Check if app can see media
oc exec -n media-stack deployment/sonarr -- ls -la /mnt/media

# Check if rclone sidecar is running
oc get pods -n media-stack -l app=sonarr -o jsonpath='{.items[0].spec.containers[*].name}'
```

---

## Root Cause

**Technical Explanation:**
FUSE (Filesystem in Userspace) mounts are isolated to the mount namespace where they're created. When rclone runs in a standalone pod, its mounts are visible only within that pod's namespace. Other pods on the same node cannot see these mounts due to kernel namespace isolation.

**Why Standalone Mounts Fail:**
1. Rclone pod creates FUSE mount on `/mnt/media`
2. Mount is registered in rclone pod's mount namespace
3. Sonarr pod on same node sees `/mnt/media` as empty directory
4. Kernel prevents cross-namespace mount propagation for security

**The 2025-12-23 Migration:**
Prior to the sidecar pattern, we tried:
- **Approach 1:** Standalone rclone pods with `hostPath` mounts → Failed (security risk + still isolated)
- **Approach 2:** `nodeSelector` pinning apps to single node → Fragile (broke during provider migration)
- **Approach 3 (Solution):** Sidecar containers with `emptyDir` + `mountPropagation: Bidirectional`

---

## Diagnosis Steps

### 1. Verify Sidecar Pattern is Deployed
```bash
oc get deployment -n media-stack sonarr -o yaml | grep -A 20 "containers:"
```

**Expected (Correct - Sidecar Pattern):**
```yaml
containers:
  - name: sonarr
    image: linuxserver/sonarr:latest
    volumeMounts:
      - name: media
        mountPath: /mnt/media
  - name: rclone-zurg
    image: rclone/rclone:latest
    volumeMounts:
      - name: media
        mountPath: /mnt/media
        mountPropagation: Bidirectional
  - name: rclone-torbox
    image: rclone/rclone:latest
    volumeMounts:
      - name: media
        mountPath: /mnt/media
        mountPropagation: Bidirectional
volumes:
  - name: media
    emptyDir: {}
```

**Problem (Old - Standalone Pattern):**
```yaml
# NO rclone sidecars in the Deployment
# Separate rclone pod in same namespace
```

### 2. Check Mount Visibility from App Container
```bash
# From Sonarr container
oc exec -n media-stack deployment/sonarr -c sonarr -- ls /mnt/media

# Should show:
# __all__/    (Zurg cloud content)
# torrents/   (TorBox downloads)
```

### 3. Check Rclone Sidecar Logs
```bash
# Check if rclone is successfully mounting
oc logs -n media-stack deployment/sonarr -c rclone-zurg --tail=50

# Look for:
# "The service rclone has been started"
# OR errors like:
# "Failed to create file system: connection refused"
```

### 4. Verify Volume Mount Configuration
```bash
oc get deployment -n media-stack sonarr -o jsonpath='{.spec.template.spec.volumes[?(@.name=="media")]}'
```

**Expected:**
```json
{"name":"media","emptyDir":{}}
```

**Problem (Missing Parent Mount):**
If only subdirectories are mounted without the parent `emptyDir`:
```yaml
# WRONG - No parent mount
volumeMounts:
  - name: zurg-content
    mountPath: /mnt/media/__all__
  - name: torbox-content
    mountPath: /mnt/media/torrents
```

---

## Resolution

### Option 1: Add Sidecar Pattern (Recommended)

This is the **permanent solution** implemented in 2025-12-23.

#### Step 1: Update Deployment Manifest

**File:** `apps/media-stack/base/<app>-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarr
  namespace: media-stack
spec:
  template:
    spec:
      containers:
        - name: sonarr
          image: linuxserver/sonarr:latest
          volumeMounts:
            - name: config
              mountPath: /config
            - name: media
              mountPath: /mnt/media  # Parent mount
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi

        # Rclone Zurg Sidecar
        - name: rclone-zurg
          image: rclone/rclone:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              rclone mount zurg: /mnt/media/__all__ \
                --config /config/rclone.conf \
                --allow-other \
                --vfs-cache-mode writes \
                --vfs-cache-max-age 24h \
                --buffer-size 32M \
                --dir-cache-time 10m
          securityContext:
            privileged: true  # Required for FUSE
            capabilities:
              add:
                - SYS_ADMIN
          volumeMounts:
            - name: media
              mountPath: /mnt/media
              mountPropagation: Bidirectional  # CRITICAL
            - name: rclone-config
              mountPath: /config
              readOnly: true

        # Rclone TorBox Sidecar
        - name: rclone-torbox
          image: rclone/rclone:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              rclone mount torbox: /mnt/media/torrents \
                --config /config/rclone.conf \
                --allow-other \
                --vfs-cache-mode writes
          securityContext:
            privileged: true
            capabilities:
              add:
                - SYS_ADMIN
          volumeMounts:
            - name: media
              mountPath: /mnt/media
              mountPropagation: Bidirectional
            - name: rclone-config
              mountPath: /config
              readOnly: true

      volumes:
        - name: media
          emptyDir: {}  # Shared parent mount
        - name: config
          persistentVolumeClaim:
            claimName: sonarr-config
        - name: rclone-config
          secret:
            secretName: rclone-config-sealed
```

#### Step 2: Apply Changes via GitOps
```bash
git add apps/media-stack/base/sonarr-deployment.yaml
git commit -m "fix(sonarr): add rclone sidecars for mount propagation"
git push origin main

# Sync via ArgoCD
argocd app sync media-stack
```

#### Step 3: Verify Mount Visibility
```bash
# Wait for new pod to start
oc get pods -n media-stack -l app=sonarr -w

# Test mount visibility
oc exec -n media-stack deployment/sonarr -c sonarr -- ls -la /mnt/media/__all__ | head -n 10
```

**Expected Output:**
```
drwxr-xr-x  2 root root 4096 Jan  8 12:00 Movies
drwxr-xr-x  2 root root 4096 Jan  8 12:00 TV
```

### Option 2: Emergency Fix (Restart Pods on Same Node)

If sidecar pattern is already deployed but mounts are broken:

```bash
# Delete pod to trigger recreation
oc delete pod -n media-stack -l app=sonarr

# Verify new pod starts on same or different node
oc get pods -n media-stack -l app=sonarr -o wide
```

---

## Prevention

### 1. Always Use Sidecar Pattern for FUSE Mounts

**Rule:** Any app requiring rclone/FUSE mounts MUST use sidecars.

**Template Checklist:**
- [ ] Parent `emptyDir` volume named `media`
- [ ] All containers mount `/mnt/media`
- [ ] Rclone containers use `mountPropagation: Bidirectional`
- [ ] Rclone containers have `securityContext.privileged: true`

### 2. Never Use Hard `nodeSelector`

**BAD:**
```yaml
nodeSelector:
  kubernetes.io/hostname: wow-ocp-node4  # BREAKS when pod moves
```

**GOOD:**
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - wow-ocp-node2
                - wow-ocp-node3
```

### 3. Test Cross-Node Scheduling

After deploying new media apps:
```bash
# Force reschedule to different node
oc delete pod -n media-stack -l app=sonarr

# Verify mounts still work on new node
oc exec -n media-stack deployment/sonarr -c sonarr -- ls /mnt/media/__all__
```

---

## Troubleshooting

### Issue: Rclone Sidecar Fails to Start (Permission Denied)

**Symptom:**
```
Error: failed to mount FUSE fs: fusermount: failed to open /dev/fuse: Permission denied
```

**Cause:** Pod doesn't have `privileged: true` or `SYS_ADMIN` capability.

**Fix:**
```yaml
securityContext:
  privileged: true
  capabilities:
    add:
      - SYS_ADMIN
```

### Issue: Main App Container Sees Empty Directory

**Symptom:**
```bash
oc exec deployment/sonarr -c sonarr -- ls /mnt/media
# Returns empty or just shows __all__ and torrents as empty dirs
```

**Cause:** Rclone sidecars haven't finished mounting yet.

**Fix:**
Add `startupProbe` to main container to wait for mounts:
```yaml
startupProbe:
  exec:
    command:
      - /bin/sh
      - -c
      - "test -f /mnt/media/__all__/.mounted || exit 1"
  initialDelaySeconds: 30
  periodSeconds: 5
  failureThreshold: 30  # Wait up to 150 seconds
```

### Issue: Mounts Work Initially Then Disappear

**Symptom:** App works for hours/days, then suddenly shows empty directory.

**Cause:** Rclone sidecar crashed or OOM killed.

**Fix:**
Check sidecar container restarts:
```bash
oc get pods -n media-stack -l app=sonarr -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="rclone-zurg")].restartCount}'
```

If high restart count, increase resources:
```yaml
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 2Gi
```

---

## Related Issues

- **Issue:** Provider migration (Real-Debrid to TorBox)
- **Lesson:** Sidecar pattern makes provider swaps seamless
- **Documentation:** `apps/media-stack/base/zone1-deployments.yaml`

---

## Lessons Learned (2025-12-23)

1. **Never use standalone mount pods** - FUSE namespace isolation makes them invisible
2. **Always use sidecars** - Guaranteed mount visibility within pod
3. **`mountPropagation: Bidirectional` is required** - Without it, mounts don't propagate
4. **Parent `emptyDir` is mandatory** - Subdirectory mounts alone don't work
5. **Remove hard `nodeSelector`** - Sidecar pattern enables cross-node scheduling

---

## Verification Checklist

- [ ] Deployment manifest includes rclone sidecars
- [ ] `emptyDir` volume named `media` exists
- [ ] All containers mount `/mnt/media`
- [ ] Rclone sidecars use `mountPropagation: Bidirectional`
- [ ] Rclone sidecars have `privileged: true`
- [ ] Main app container can list `/mnt/media/__all__`
- [ ] Pod can be scheduled on any node (Node 2, 3, or 4)
- [ ] ArgoCD shows application as `Synced` and `Healthy`

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Owner:** SRE Team
