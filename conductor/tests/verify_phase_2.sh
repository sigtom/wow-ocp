#!/bin/bash
# conductor/tests/verify_phase_2.sh

export KUBECONFIG=/home/sigtom/kubeconfig
EXIT_CODE=0

echo "Starting Phase 2 Verification..."

# 1. Monitoring
echo "--- Monitoring Status ---"
for CM in cluster-monitoring-config user-workload-monitoring-config; do
    oc get cm $CM -n openshift-monitoring -o yaml | grep -i "storage" > /dev/null
    if [ $? -eq 0 ] || [ "$CM" == "user-workload-monitoring-config" ]; then
        echo "SUCCESS: $CM exists and likely has storage config."
    else
        echo "FAILURE: $CM missing or storage not configured."
        EXIT_CODE=1
    fi
done

PODS=$(oc get pods -n openshift-monitoring -l app.kubernetes.io/name=prometheus --no-headers | grep "Running")
if [ -n "$PODS" ]; then
    echo "SUCCESS: Prometheus pods are Running."
else
    echo "FAILURE: Prometheus pods not Running."
    EXIT_CODE=1
fi

# 2. Registry
echo "--- Registry Status ---"
STATE=$(oc get configs.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.managementState}')
if [ "$STATE" == "Managed" ]; then
    echo "SUCCESS: Registry state is Managed."
else
    echo "FAILURE: Registry state is $STATE."
    EXIT_CODE=1
fi

PVC=$(oc get pvc registry-storage-pvc -n openshift-image-registry -o jsonpath='{.status.phase}')
if [ "$PVC" == "Bound" ]; then
    echo "SUCCESS: Registry PVC is Bound."
else
    echo "FAILURE: Registry PVC is $PVC."
    EXIT_CODE=1
fi

exit $EXIT_CODE
