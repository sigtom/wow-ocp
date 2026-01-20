# Runbook 005: Cert-Manager Certificate Issuance Failures

**Frequency:** Occasional (new apps, DNS changes, API token rotation)
**Impact:** Medium - Apps unreachable via HTTPS (HTTP still works)
**Last Occurred:** 2025-12-23 (during wildcard cert deployment)
**MTTR:** 10-30 minutes

---

## Symptoms

- Ingress shows TLS secret not found or invalid
- Browser shows "Certificate not trusted" or "NET::ERR_CERT_INVALID"
- Cert-Manager logs show ACME challenge failures
- Certificate CR shows `Ready: False`

**Quick Check:**
```bash
# Check certificate status
oc get certificate -A

# Describe specific certificate
oc describe certificate <cert-name> -n <namespace>
```

---

## Root Cause Analysis

### Common Causes (Priority Order)

1. **Cloudflare API Token Invalid/Expired** (40% of cases)
   - Token rotated but secret not updated
   - Token lacks DNS edit permissions
   - API rate limit exceeded

2. **DNS-01 Challenge Failure** (30% of cases)
   - TXT record not created on Cloudflare
   - DNS propagation delay (>5 minutes)
   - Wrong Cloudflare Zone ID

3. **ClusterIssuer Misconfiguration** (15% of cases)
   - Wrong ACME server URL
   - Invalid email address
   - Missing or wrong secret reference

4. **Let's Encrypt Rate Limits** (10% of cases)
   - >5 duplicate cert requests in 1 week
   - >50 certs per domain per week

5. **Ingress Annotation Error** (5% of cases)
   - Wrong ClusterIssuer name
   - Missing `cert-manager.io/cluster-issuer` annotation

---

## Diagnosis Steps

### Step 1: Check Certificate Status
```bash
oc get certificate -n <namespace> <cert-name>
```

**Expected (Success):**
```
NAME        READY   SECRET           AGE
my-app-tls  True    my-app-tls       10d
```

**Problem (Failure):**
```
NAME        READY   SECRET           AGE
my-app-tls  False   my-app-tls       5m
```

### Step 2: Describe Certificate for Events
```bash
oc describe certificate <cert-name> -n <namespace>
```

**Look for Events:**
```
Events:
  Type     Reason        Message
  ----     ------        -------
  Warning  Issuing       Failed to create Order: acme: urn:ietf:params:acme:error:rateLimited
  Normal   Issuing       Renewing certificate as it has passed two thirds of its duration
  Warning  BadConfig     Failed to determine DNS zone for domain
```

**Common Event Messages:**

| Message | Cause | Runbook Section |
|---------|-------|-----------------|
| `Failed to create Order: unauthorized` | Cloudflare API token invalid | Fix 1 |
| `DNS record not found` | DNS-01 challenge failed | Fix 2 |
| `rateLimited` | Let's Encrypt rate limit | Fix 4 |
| `Failed to determine DNS zone` | Wrong Cloudflare Zone ID | Fix 3 |

### Step 3: Check CertificateRequest
```bash
# Find the CertificateRequest linked to Certificate
oc get certificaterequest -n <namespace>

# Describe it
oc describe certificaterequest <cert-name>-xxxxx -n <namespace>
```

### Step 4: Check ACME Challenge
```bash
# List challenges
oc get challenge -n <namespace>

# Describe failed challenge
oc describe challenge <challenge-name> -n <namespace>
```

**Look for:**
```
Status:
  Presented:   true
  Processing:  true
  Reason:      Waiting for DNS-01 challenge propagation
  State:       pending
```

**If stuck in `pending` for >10 minutes:** DNS issue.

### Step 5: Check Cert-Manager Logs
```bash
oc logs -n cert-manager deployment/cert-manager --tail=100 | grep -i error
```

**Common Log Patterns:**

| Log Message | Action |
|-------------|--------|
| `cloudflare API error: invalid token` | Update API token secret |
| `cloudflare API error: rate limit` | Wait 1 hour, use staging for testing |
| `DNS record not found after 600s` | Check DNS propagation manually |
| `acme: error: 429: too many requests` | Hit Let's Encrypt rate limit |

### Step 6: Verify Cloudflare API Token Permissions

**Required Permissions:**
- Zone → DNS → Edit
- Zone → Zone → Read

**Test Token Manually:**
```bash
# Get token from secret
TOKEN=$(oc get secret cloudflare-api-token-sealed -n cert-manager -o jsonpath='{.data.api-token}' | base64 -d)

# Test API access
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json"
```

**Expected:**
```json
{
  "success": true,
  "result": [
    {
      "id": "ZONE_ID",
      "name": "sigtomtech.com",
      ...
    }
  ]
}
```

**Problem:**
```json
{
  "success": false,
  "errors": [
    {
      "code": 6003,
      "message": "Invalid request headers"
    }
  ]
}
```

---

## Resolution

### Fix 1: Update Cloudflare API Token

**Symptom:** Cert-Manager logs show `invalid token` or `unauthorized`.

**Resolution:**

1. Generate new token on Cloudflare:
   - Go to: https://dash.cloudflare.com/profile/api-tokens
   - Click "Create Token"
   - Use template: "Edit zone DNS"
   - Zone Resources: Include → Specific zone → `sigtomtech.com`

2. Create SealedSecret:
```bash
# Create raw secret
oc create secret generic cloudflare-api-token \
  --from-literal=api-token=<NEW_TOKEN> \
  --dry-run=client -o yaml > /tmp/cloudflare-secret.yaml

# Seal it
kubeseal --cert pub-sealed-secrets.pem \
  --format yaml < /tmp/cloudflare-secret.yaml \
  > infrastructure/operators/cert-manager/base/cloudflare-sealed-secret.yaml

# Cleanup
rm /tmp/cloudflare-secret.yaml

# Commit and push
git add infrastructure/operators/cert-manager/base/cloudflare-sealed-secret.yaml
git commit -m "fix(cert-manager): rotate cloudflare api token"
git push origin main

# Sync via ArgoCD
argocd app sync cert-manager-operator
```

3. Restart Cert-Manager to pick up new secret:
```bash
oc delete pod -n cert-manager -l app=cert-manager
```

4. Trigger certificate reissuance:
```bash
# Delete failed certificate to force retry
oc delete certificate <cert-name> -n <namespace>

# Certificate will be recreated by Ingress controller
```

### Fix 2: DNS-01 Challenge Stuck (Propagation Delay)

**Symptom:** Challenge shows `Waiting for DNS-01 challenge propagation` for >10 minutes.

**Resolution:**

1. Verify TXT record was created on Cloudflare:
```bash
# Get challenge domain
oc get challenge -n <namespace> -o jsonpath='{.items[0].spec.dnsName}'

# Query Cloudflare DNS
dig _acme-challenge.<domain>.sigtomtech.com TXT @1.1.1.1
```

**Expected:**
```
;; ANSWER SECTION:
_acme-challenge.myapp.sigtomtech.com. 120 IN TXT "ACME_VALIDATION_STRING"
```

**Problem (No TXT record):**
- Cert-Manager couldn't create record (check API token)
- Delete challenge to retry:
```bash
oc delete challenge <challenge-name> -n <namespace>
```

2. If TXT record exists but validation fails:
```bash
# Manually verify from external DNS
dig _acme-challenge.<domain>.sigtomtech.com TXT @8.8.8.8

# If not visible, wait 5 more minutes for propagation
```

### Fix 3: Wrong Cloudflare Zone ID

**Symptom:** Cert-Manager logs show `Failed to determine DNS zone`.

**Resolution:**

1. Get correct Zone ID from Cloudflare:
   - Dashboard → Select domain → Overview → API section → Zone ID

2. Update ClusterIssuer:

**File:** `infrastructure/operators/cert-manager/base/cluster-issuer.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cloudflare-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@sigtomtech.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-sealed
              key: api-token
            # ADD THIS if missing:
            # email: admin@sigtomtech.com  # Cloudflare account email
```

3. Apply via GitOps:
```bash
git add infrastructure/operators/cert-manager/base/cluster-issuer.yaml
git commit -m "fix(cert-manager): add cloudflare account email"
git push origin main

argocd app sync cert-manager-operator
```

### Fix 4: Let's Encrypt Rate Limit Hit

**Symptom:** Certificate shows `rateLimited` error.

**Rate Limits:**
- **Duplicate Certificate Limit:** 5 per week
- **Certificates per Registered Domain:** 50 per week
- **Failed Validation Limit:** 5 per account per hostname per hour

**Resolution (Option A: Wait):**
```bash
# Check rate limit reset time (usually 1 week from first request)
oc describe certificate <cert-name> -n <namespace> | grep "Not After"
```

**Resolution (Option B: Use Staging for Testing):**

Create separate ClusterIssuer for testing:

**File:** `infrastructure/operators/cert-manager/base/cluster-issuer-staging.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cloudflare-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory  # STAGING
    email: admin@sigtomtech.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-sealed
              key: api-token
```

**Use in Ingress:**
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: cloudflare-staging  # Use staging
```

**⚠️ Staging certs are NOT TRUSTED by browsers** - only for testing.

### Fix 5: Missing or Wrong Ingress Annotation

**Symptom:** Certificate not created automatically for Ingress.

**Resolution:**

**Check Ingress:**
```bash
oc get ingress <ingress-name> -n <namespace> -o yaml
```

**Ensure these annotations exist:**
```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: cloudflare-prod  # REQUIRED
    route.openshift.io/termination: edge
    route.openshift.io/insecure-policy: Redirect
spec:
  tls:
    - hosts:
        - myapp.apps.ossus.sigtomtech.com
      secretName: myapp-tls  # Cert-Manager creates this
```

---

## Prevention

### 1. Use Wildcard Certificate (Recommended)

**Deployed:** 2025-12-23 for `*.apps.ossus.sigtomtech.com`

**File:** `infrastructure/operators/cert-manager/base/cluster-ingress/wildcard-cert.yaml`

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-apps-cert
  namespace: openshift-ingress
spec:
  secretName: wildcard-apps-tls
  issuerRef:
    name: cloudflare-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.apps.ossus.sigtomtech.com"
    - "apps.ossus.sigtomtech.com"
```

**Benefits:**
- One cert for all apps
- Avoids per-app rate limits
- Automatic renewal (90 days)

### 2. Monitor Certificate Expiry

**File:** `infrastructure/monitoring/cert-expiry-alerts.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cert-expiry-alerts
  namespace: openshift-monitoring
spec:
  groups:
    - name: certificates
      rules:
        - alert: CertificateExpiringSoon
          expr: |
            certmanager_certificate_expiration_timestamp_seconds - time() < (21 * 24 * 3600)
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Certificate expiring in <21 days"
            description: "Certificate {{ $labels.name }} in {{ $labels.namespace }} expires in {{ $value | humanizeDuration }}"

        - alert: CertificateNotReady
          expr: |
            certmanager_certificate_ready_status{condition="False"} > 0
          for: 15m
          labels:
            severity: critical
          annotations:
            summary: "Certificate not ready"
            description: "Certificate {{ $labels.name }} in {{ $labels.namespace }} is not ready"
```

### 3. Document Token Rotation Procedure

**Schedule:** Every 90 days

1. Generate new Cloudflare API token
2. Create SealedSecret
3. Commit to Git
4. Sync ArgoCD
5. Restart Cert-Manager pods
6. Verify cert renewals work

---

## Troubleshooting

### Issue: Certificate Shows "Ready: True" But Browser Shows Invalid

**Cause:** Old certificate cached in browser or Ingress Controller.

**Fix:**
```bash
# Delete Route secret to force recreation
oc delete secret <cert-name>-tls -n <namespace>

# Restart Ingress Controller pods
oc delete pod -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default

# Clear browser cache or test in incognito
```

### Issue: Multiple Failed CertificateRequests Piling Up

**Symptom:**
```bash
oc get certificaterequest -n <namespace>
# Shows 10+ failed requests
```

**Fix:**
```bash
# Clean up old failed requests
oc delete certificaterequest -n <namespace> --field-selector=status.conditions[0].status=False

# Delete and recreate Certificate
oc delete certificate <cert-name> -n <namespace>
```

### Issue: Staging Certificate Works But Prod Fails

**Cause:** Likely rate limit on prod Let's Encrypt.

**Fix:**
- Wait 7 days for rate limit reset
- Verify staging works correctly first
- Switch to prod ClusterIssuer only when confident config is correct

---

## Related Issues

- **Issue:** Wildcard cert deployment (2025-12-23)
- **Documentation:** `infrastructure/operators/cert-manager/base/`
- **Architecture Decision:** Use Ingress over Routes for TLS automation

---

## Lessons Learned (2025-12-23)

1. **Wildcard certs reduce complexity** - One cert for all apps, no per-app management
2. **Always test with staging first** - Avoid hitting prod rate limits
3. **Use Kubernetes Ingress in Git** - Better integration with Cert-Manager than Routes
4. **Monitor token expiry** - Set calendar reminder for 90-day rotation
5. **DNS propagation takes time** - Wait 5-10 minutes for TXT record visibility

---

## Verification Checklist

- [ ] Certificate shows `Ready: True`
- [ ] Secret exists: `oc get secret <cert-name>-tls -n <namespace>`
- [ ] Browser shows "green lock" for HTTPS URL
- [ ] Certificate valid dates: `oc get certificate <cert-name> -n <namespace> -o jsonpath='{.status.notAfter}'`
- [ ] No rate limit errors in Cert-Manager logs
- [ ] Cloudflare API token has correct permissions

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Owner:** SRE Team
