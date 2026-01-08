#!/bin/bash
set -euo pipefail

#############################################################################
# check-pod.sh - Diagnose Pod Crash and Startup Issues
#
# Purpose: Comprehensive pod troubleshooting for OpenShift homelab
# Author: Senior SRE (Gen X Edition)
# Version: 1.0
#############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}" >&2
}

info() {
    echo -e "${BLUE}→ INFO: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ SUCCESS: $1${NC}" >&2
}

section() {
    echo -e "\n${BLUE}━━━ $1 ━━━${NC}" >&2
}

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 <pod-name> <namespace>

${BLUE}Description:${NC}
  Diagnose pod crash and startup issues in OpenShift homelab.
  
  Analyzes:
    • Pod status and events
    • Current and previous container logs
    • Resource limits (CPU/memory OOM)
    • Liveness/readiness probe failures
    • Image pull issues
    • Volume mount problems

${BLUE}Examples:${NC}
  $0 plex-7d4b8f9c-xk2l9 media
  $0 my-app-pod default

${BLUE}Prerequisites:${NC}
  • oc CLI configured with cluster access
EOF
    exit 1
}

# Argument parsing
if [[ $# -ne 2 ]]; then
    usage
fi

POD_NAME="$1"
NAMESPACE="$2"

# Preflight checks
if ! command -v oc &> /dev/null; then
    error "oc CLI not found. Install OpenShift CLI tools."
    exit 1
fi

if ! oc whoami &> /dev/null; then
    error "Not logged into OpenShift cluster. Run: oc login"
    exit 1
fi

section "Pod Status Check"

# Check if pod exists
if ! oc get pod "${POD_NAME}" -n "${NAMESPACE}" &> /dev/null; then
    error "Pod '${POD_NAME}' not found in namespace '${NAMESPACE}'"
    exit 1
fi

# Get pod status
POD_STATUS=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}')
POD_READY=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
RESTART_COUNT=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

info "Pod Status: ${POD_STATUS}"
info "Ready: ${POD_READY}"
info "Restart Count: ${RESTART_COUNT}"

if [[ "${POD_STATUS}" == "Running" && "${POD_READY}" == "True" && "${RESTART_COUNT}" == "0" ]]; then
    success "Pod is healthy and running"
    exit 0
fi

# Get container statuses
CONTAINER_STATES=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[*].state}')

if echo "${CONTAINER_STATES}" | grep -qi "CrashLoopBackOff"; then
    error "Pod is in CrashLoopBackOff - container keeps crashing"
elif echo "${CONTAINER_STATES}" | grep -qi "ImagePullBackOff\|ErrImagePull"; then
    error "Image pull failed - check image name and pull secrets"
elif echo "${CONTAINER_STATES}" | grep -qi "OOMKilled"; then
    error "Container was OOMKilled - increase memory limits"
fi

section "Pod Events"

# Get events
EVENTS=$(oc get events -n "${NAMESPACE}" --field-selector involvedObject.name="${POD_NAME}" --sort-by='.lastTimestamp' 2>/dev/null | tail -15)

if [[ -z "${EVENTS}" ]]; then
    warning "No events found for pod"
else
    echo "${EVENTS}"
    
    # Check for common error patterns
    if echo "${EVENTS}" | grep -qi "OOMKilled"; then
        error "Container killed due to out of memory"
        warning "Increase memory limits in pod spec"
    fi
    
    if echo "${EVENTS}" | grep -qi "Liveness probe failed"; then
        error "Liveness probe failing - container may be unhealthy"
        warning "Check liveness probe configuration and endpoint"
    fi
    
    if echo "${EVENTS}" | grep -qi "Readiness probe failed"; then
        warning "Readiness probe failing - container not ready for traffic"
    fi
    
    if echo "${EVENTS}" | grep -qi "FailedMount\|MountVolume"; then
        error "Volume mount failed - check PVC status"
        warning "Run: ./check-pvc.sh <pvc-name> ${NAMESPACE}"
    fi
    
    if echo "${EVENTS}" | grep -qi "ImagePull"; then
        error "Image pull failed - check image name, tag, and credentials"
    fi
fi

section "Resource Limits"

# Get resource requests/limits
RESOURCES=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].resources}' 2>/dev/null)

if [[ -n "${RESOURCES}" && "${RESOURCES}" != "{}" ]]; then
    info "Container resources:"
    oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{range .spec.containers[*]}{"Container: "}{.name}{"\n"}{"  Requests: "}{.resources.requests}{"\n"}{"  Limits: "}{.resources.limits}{"\n"}{end}'
    
    # Check for no limits
    NO_LIMITS=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[?(@.resources.limits=="")].name}' 2>/dev/null)
    if [[ -n "${NO_LIMITS}" ]]; then
        warning "Container(s) without resource limits: ${NO_LIMITS}"
        warning "This can cause cluster instability - add resource limits"
    fi
else
    warning "No resource limits defined - add requests/limits to prevent OOM"
fi

section "Liveness & Readiness Probes"

# Check probes
HAS_LIVENESS=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].livenessProbe}' 2>/dev/null)
HAS_READINESS=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].readinessProbe}' 2>/dev/null)

if [[ -z "${HAS_LIVENESS}" ]]; then
    warning "No liveness probe configured - Kubernetes can't detect unhealthy containers"
else
    success "Liveness probe configured"
    oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{range .spec.containers[*]}{"Container: "}{.name}{"\n"}{"  Liveness: "}{.livenessProbe}{"\n"}{end}'
fi

if [[ -z "${HAS_READINESS}" ]]; then
    warning "No readiness probe configured - pod may receive traffic before ready"
else
    success "Readiness probe configured"
    oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{range .spec.containers[*]}{"Container: "}{.name}{"\n"}{"  Readiness: "}{.readinessProbe}{"\n"}{end}'
fi

section "Container Logs (Current - Last 50 lines)"

# Get container names
CONTAINERS=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].name}')

for container in ${CONTAINERS}; do
    info "Container: ${container}"
    
    # Get current logs
    LOGS=$(oc logs "${POD_NAME}" -n "${NAMESPACE}" -c "${container}" --tail=50 2>&1)
    
    if echo "${LOGS}" | grep -qi "error\|fail\|fatal\|panic\|crash"; then
        error "Errors found in current logs:"
        echo "${LOGS}" | grep -i "error\|fail\|fatal\|panic\|crash" | tail -10
    else
        echo "${LOGS}" | tail -10
    fi
done

section "Previous Container Logs (If Crashed)"

for container in ${CONTAINERS}; do
    info "Container: ${container} (previous instance)"
    
    # Try to get previous logs
    PREV_LOGS=$(oc logs "${POD_NAME}" -n "${NAMESPACE}" -c "${container}" --previous --tail=50 2>&1 || echo "No previous logs available")
    
    if [[ "${PREV_LOGS}" != "No previous logs available" ]]; then
        if echo "${PREV_LOGS}" | grep -qi "error\|fail\|fatal\|panic\|crash\|oom"; then
            error "Errors in previous logs (before crash):"
            echo "${PREV_LOGS}" | grep -i "error\|fail\|fatal\|panic\|crash\|oom" | tail -10
        else
            echo "${PREV_LOGS}" | tail -10
        fi
    else
        info "No previous container logs (first start or not crashed yet)"
    fi
done

section "Image Information"

# Get images
IMAGES=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].image}')
info "Images in use:"
for image in ${IMAGES}; do
    echo "  - ${image}"
done

# Check for latest tag
if echo "${IMAGES}" | grep -q ":latest"; then
    warning "Using ':latest' tag - not recommended for production"
    warning "Pin to specific versions for reproducible deployments"
fi

section "Volume Mounts"

# Check volume mounts
VOLUME_MOUNTS=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].volumeMounts}' 2>/dev/null)

if [[ -n "${VOLUME_MOUNTS}" && "${VOLUME_MOUNTS}" != "null" ]]; then
    info "Volume mounts:"
    oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{range .spec.containers[*]}{"Container: "}{.name}{"\n"}{range .volumeMounts}{"  "}{.name}{" -> "}{.mountPath}{" (propagation: "}{.mountPropagation}{")"}{"\n"}{end}{end}'
    
    # Check for Bidirectional propagation (needed for FUSE mounts)
    BIDI=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[*].volumeMounts[?(@.mountPropagation=="Bidirectional")].name}' 2>/dev/null)
    if [[ -n "${BIDI}" ]]; then
        success "Found Bidirectional mount propagation (required for FUSE/Rclone)"
    fi
    
    # Check for mount failures
    if echo "${EVENTS}" | grep -qi "MountVolume.SetUp failed"; then
        error "Volume mount failed - check PVC or volume configuration"
    fi
else
    info "No volume mounts"
fi

section "Node Information"

# Get node assignment
NODE_NAME=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.nodeName}')
if [[ -n "${NODE_NAME}" ]]; then
    info "Running on node: ${NODE_NAME}"
    
    # Check node status
    NODE_STATUS=$(oc get node "${NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [[ "${NODE_STATUS}" == "True" ]]; then
        success "Node is Ready"
    else
        error "Node is not Ready - may be experiencing issues"
    fi
    
    # Check node pressure
    NODE_PRESSURE=$(oc get node "${NODE_NAME}" -o jsonpath='{.status.conditions[?(@.status=="True")].type}' | grep -i "pressure" || true)
    if [[ -n "${NODE_PRESSURE}" ]]; then
        error "Node experiencing pressure: ${NODE_PRESSURE}"
        warning "Node may be out of resources (disk, memory, or PIDs)"
    fi
else
    warning "Pod not yet scheduled to a node"
fi

section "Summary & Recommendations"

info "Pod: ${POD_NAME}"
info "Namespace: ${NAMESPACE}"
info "Status: ${POD_STATUS}"
info "Ready: ${POD_READY}"
info "Restarts: ${RESTART_COUNT}"

echo -e "\n${YELLOW}Recommendations:${NC}"

if [[ "${RESTART_COUNT}" -gt 5 ]]; then
    echo "1. Pod has restarted ${RESTART_COUNT} times - investigate logs above"
fi

if [[ -z "${HAS_LIVENESS}" || -z "${HAS_READINESS}" ]]; then
    echo "2. Add liveness and readiness probes to pod spec"
fi

if [[ -z "${RESOURCES}" || "${RESOURCES}" == "{}" ]]; then
    echo "3. Add resource requests and limits to prevent OOM and ensure QoS"
fi

if echo "${EVENTS}" | grep -qi "FailedMount"; then
    echo "4. Check PVC status: ./check-pvc.sh <pvc-name> ${NAMESPACE}"
fi

if echo "${EVENTS}" | grep -qi "ImagePull"; then
    echo "5. Verify image exists and pull secret is configured"
fi

if echo "${CONTAINER_STATES}" | grep -qi "CrashLoopBackOff"; then
    echo "6. Review previous container logs above for crash cause"
fi

echo -e "\n${BLUE}Next Steps:${NC}"
echo "• View full logs: oc logs ${POD_NAME} -n ${NAMESPACE} --all-containers --previous"
echo "• Describe pod: oc describe pod ${POD_NAME} -n ${NAMESPACE}"
echo "• Debug shell: oc debug pod/${POD_NAME} -n ${NAMESPACE}"
echo "• Check events: oc get events -n ${NAMESPACE} --sort-by='.lastTimestamp'"

exit 0
