#!/bin/bash
# conductor/tests/verify_vlan_110.sh

export KUBECONFIG=/home/sigtom/kubeconfig
NODES=$(oc get nodes -o name)
EXIT_CODE=0
declare -A NODE_IPS

echo "Starting VLAN 110 Verification..."

for NODE in $NODES; do
    echo "--- Checking $NODE ---"
    # Find IP in 172.16.110.x range
    IP=$(oc debug $NODE --quiet -- chroot /host ip -4 addr show | grep -oP '172\.16\.110\.\d+' | head -n 1)
    if [ -n "$IP" ]; then
        echo "SUCCESS: Found IP $IP on $NODE"
        NODE_IPS[$NODE]=$IP
    else
        echo "FAILURE: No 172.16.110.x IP found on $NODE"
        EXIT_CODE=1
    fi
done

# Connectivity Test
echo "--- Connectivity Matrix ---"
for SRC_NODE in "${!NODE_IPS[@]}"; do
    for DST_NODE in "${!NODE_IPS[@]}"; do
        if [ "$SRC_NODE" == "$DST_NODE" ]; then continue; fi
        
        SRC_NAME=$(echo $SRC_NODE | cut -d'/' -f2)
        DST_IP=${NODE_IPS[$DST_NODE]}
        
        echo -n "Testing $SRC_NAME -> $DST_IP: "
        oc debug $SRC_NODE --quiet -- chroot /host ping -c 2 -W 2 $DST_IP > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "SUCCESS"
        else
            echo "FAILURE"
            EXIT_CODE=1
        fi
    done
done

exit $EXIT_CODE
