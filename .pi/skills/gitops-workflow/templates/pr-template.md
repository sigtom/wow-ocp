# Pull Request Description

## What Changed

<!-- List the changes made in this PR -->

- [ ] Added/Modified: ...
- [ ] Removed: ...
- [ ] Updated: ...

## Why It Changed

<!-- Explain the motivation or problem being solved -->

<!-- Example:
Plex pod was unable to access media library due to FUSE mount propagation
issues. This PR adds an rclone sidecar with bidirectional mount propagation
to resolve the issue.
-->

## How to Verify

<!-- Steps to verify the changes work as expected -->

1. After merge: `argocd app sync <app-name>`
2. Check pod status: `oc get pods -n <namespace>`
3. Verify functionality: ...
4. Check logs: `oc logs -n <namespace> deployment/<name>`

## Related Issues

<!-- Link to related issues or PRs -->

- Fixes #
- Closes #
- Refs #
- Related to #

## Pre-Merge Checklist

<!-- Ensure all items are checked before requesting review -->

- [ ] **Validated manifests:** Ran `./scripts/validate.sh [path]`
- [ ] **Tested dry-run:** `kustomize build | oc apply --dry-run=client -f -`
- [ ] **Resource limits present:** All Deployments have `resources.requests` and `resources.limits`
- [ ] **Health probes present:** All Deployments have `livenessProbe` and `readinessProbe`
- [ ] **No raw secrets:** Only `SealedSecret` resources committed (verified with `grep -r "kind: Secret"`)
- [ ] **Conventional commit:** Commit messages follow `<type>: <description>` format
- [ ] **Ingress annotations:** If added/modified Ingress, includes `cert-manager.io/cluster-issuer` and `route.openshift.io/termination`
- [ ] **ArgoCD Application:** If new app, added ArgoCD Application CRD to `argocd-apps/`
- [ ] **Documentation updated:** README or inline comments added if needed
- [ ] **Conflicts resolved:** Branch is up-to-date with `main`

## Post-Merge Actions

<!-- Actions to take after PR is merged -->

- [ ] Verify ArgoCD sync: `argocd app get <app-name>`
- [ ] Check pod health: `oc get pods -n <namespace>`
- [ ] Update PROGRESS.md: `./scripts/update-progress.sh "<description>"`
- [ ] Delete branch: `git branch -d <branch-name>`

## Screenshots (Optional)

<!-- Add screenshots if relevant (UI changes, dashboards, etc.) -->

## Additional Notes

<!-- Any other context, warnings, or considerations -->

---

## Reviewer Guidance

<!-- Help reviewers know what to focus on -->

**Focus areas:**
- [ ] Resource limits appropriate for workload size
- [ ] NetworkPolicy doesn't block required traffic
- [ ] Secrets properly encrypted (SealedSecret)
- [ ] Manifests follow repository conventions
- [ ] No hardcoded values (use ConfigMap or environment variables)

**Testing recommendations:**
- [ ] Dry-run passes: `kustomize build <path> | oc apply --dry-run=client -f -`
- [ ] Kustomize builds without errors: `kustomize build <path>`
- [ ] YAML syntax valid: `yamllint <path>`

---

## Example: Feature PR

```markdown
# Pull Request Description

## What Changed

- [x] Added Bazarr deployment with rclone sidecar
- [x] Created PVC for persistent storage (NFS, 10Gi)
- [x] Added Service (ClusterIP) and Ingress with TLS
- [x] Configured NetworkPolicy for same-namespace traffic
- [x] Created ArgoCD Application CRD

## Why It Changed

Bazarr automates subtitle downloads for media library content. Integrates
with Sonarr and Radarr to fetch subtitles for TV shows and movies.

## How to Verify

1. After merge: `argocd app sync bazarr`
2. Check pod status: `oc get pods -n bazarr`
3. Access UI: https://bazarr.apps.wow.sigtomtech.com
4. Configure Sonarr/Radarr integration in UI
5. Verify subtitle downloads work

## Related Issues

- Closes #78
- Related to #42 (media stack architecture)

## Pre-Merge Checklist

- [x] Validated manifests: Ran `./scripts/validate.sh apps/bazarr/base`
- [x] Tested dry-run: All resources pass dry-run
- [x] Resource limits present: 500m/512Mi requests, 2000m/2Gi limits
- [x] Health probes present: HTTP probes on /health and /ready
- [x] No raw secrets: Using existing Sonarr API key SealedSecret
- [x] Conventional commit: `feat: add Bazarr for subtitle management`
- [x] Ingress annotations: cert-manager and route termination configured
- [x] ArgoCD Application: Created `argocd-apps/bazarr.yaml`
- [x] Documentation updated: Added to media-stack README
- [x] Conflicts resolved: Rebased on latest main

## Post-Merge Actions

- [ ] Verify ArgoCD sync: `argocd app get bazarr`
- [ ] Check pod health: `oc get pods -n bazarr`
- [ ] Update PROGRESS.md: Deployment of Bazarr
- [ ] Delete branch: `git branch -d feature/add-bazarr`

## Additional Notes

Bazarr requires Sonarr and Radarr API keys for integration. These are
stored in SealedSecrets and mounted as environment variables.

Rclone sidecar provides access to media library on TorBox mount.

---

## Reviewer Guidance

**Focus areas:**
- [x] Resource limits appropriate (similar to Sonarr/Radarr)
- [x] NetworkPolicy allows traffic from same namespace
- [x] Rclone sidecar configuration matches other media apps
- [x] No hardcoded API keys or credentials

**Testing recommendations:**
- [x] Dry-run passes: `kustomize build apps/bazarr/base | oc apply --dry-run=client -f -`
- [x] Kustomize builds: `kustomize build apps/bazarr/base`
- [x] YAML valid: `yamllint apps/bazarr/base/*.yaml`
```

---

## Example: Bug Fix PR

```markdown
# Pull Request Description

## What Changed

- [x] Fixed Sonarr PVC mount permissions (securityContext.fsGroup)
- [x] Updated rclone sidecar mount propagation to bidirectional

## Why It Changed

Sonarr pod was unable to write to /config directory on NFS PVC. Root cause
was missing fsGroup in securityContext, causing permission denied errors.

Also resolved FUSE mount visibility issue by changing mount propagation
from HostToContainer to Bidirectional.

## How to Verify

1. After merge: `argocd app sync sonarr`
2. Check pod recreates: `oc get pods -n sonarr -w`
3. Exec into pod: `oc exec -n sonarr deployment/sonarr -- ls -la /config`
4. Verify writes work: `oc exec -n sonarr deployment/sonarr -- touch /config/test.txt`
5. Check logs for errors: `oc logs -n sonarr deployment/sonarr`

## Related Issues

- Fixes #92

## Pre-Merge Checklist

- [x] Validated manifests: Ran `./scripts/validate.sh apps/sonarr/base`
- [x] Tested dry-run: Resource updates pass dry-run
- [x] Resource limits present: Unchanged from existing
- [x] Health probes present: Unchanged from existing
- [x] No raw secrets: No secrets modified
- [x] Conventional commit: `fix: resolve Sonarr PVC mount permissions`
- [x] Ingress annotations: No Ingress changes
- [x] ArgoCD Application: No Application changes
- [x] Documentation updated: Added troubleshooting note to README
- [x] Conflicts resolved: No conflicts with main

## Post-Merge Actions

- [ ] Verify ArgoCD sync: `argocd app get sonarr`
- [ ] Check pod recreates: `oc get pods -n sonarr`
- [ ] Update PROGRESS.md: Fixed Sonarr mount permissions
- [ ] Delete branch: `git branch -d fix/sonarr-pvc-permissions`

## Additional Notes

This fix applies to all media apps using NFS PVCs. May need to apply
similar changes to Radarr, Bazarr, etc.

---

## Reviewer Guidance

**Focus areas:**
- [x] fsGroup value matches NFS server UID/GID
- [x] Mount propagation doesn't break other pods

**Testing recommendations:**
- [x] Dry-run passes: `kustomize build apps/sonarr/base | oc apply --dry-run=client -f -`
```
