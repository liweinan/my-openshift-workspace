#!/bin/bash

# Verify zone consistency of machines in an installed cluster
# Usage: ./verify-cluster.sh [kubeconfig_path]

set -e

KUBECONFIG_PATH="${1:-${KUBECONFIG}}"

if [ -z "$KUBECONFIG_PATH" ]; then
    echo "Error: kubeconfig path not specified"
    echo "Usage: $0 <kubeconfig_path>"
    echo "Or set KUBECONFIG environment variable"
    exit 1
fi

if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "Error: kubeconfig file does not exist: $KUBECONFIG_PATH"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

echo "=========================================="
echo "Verify Machine Zone Consistency in Cluster"
echo "=========================================="
echo ""
echo "Kubeconfig: $KUBECONFIG_PATH"
echo ""

# Check required tools
if ! command -v oc >/dev/null 2>&1; then
    echo "Error: oc tool is required"
    echo "Install: visit https://mirror.openshift.com/pub/openshift-v4/clients/ocp/"
    exit 1
fi

# Check cluster connection
if ! oc cluster-info >/dev/null 2>&1; then
    echo "Error: Cannot connect to cluster"
    echo "Please check if kubeconfig file is correct"
    exit 1
fi

echo "✓ Successfully connected to cluster"
echo ""

# Get all master machines
MASTER_MACHINES=$(oc get machine -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-role=master -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -z "$MASTER_MACHINES" ]; then
    echo "❌ Error: No master machines found"
    echo "   Please ensure the cluster installation is complete"
    exit 1
fi

echo "Found $(echo $MASTER_MACHINES | wc -w | tr -d ' ') master machine(s)"
echo ""

# Verify zone consistency for each machine
echo "=========================================="
echo "Check Zone Consistency for Each Machine"
echo "=========================================="
echo ""

all_consistent=true
machine_count=0

for machine in $MASTER_MACHINES; do
    machine_count=$((machine_count + 1))
    echo "--- Machine: $machine ---"
    
    # Get zone label
    zone_label=$(oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.metadata.labels.machine\.openshift\.io/zone}' 2>/dev/null || echo "N/A")
    
    # Get zone from providerID
    provider_id=$(oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.spec.providerID}' 2>/dev/null || echo "")
    provider_zone=$(echo "$provider_id" | grep -oP 'aws:///\K[^/]+' 2>/dev/null || echo "N/A")
    
    # Get availabilityZone from spec
    spec_zone=$(oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.placement.availabilityZone}' 2>/dev/null || echo "N/A")
    
    # Get subnet information (if using subnet filter)
    subnet_filter=$(oc get machine "$machine" -n openshift-machine-api -o jsonpath='{.spec.providerSpec.value.subnet.filters[*].values[0]}' 2>/dev/null || echo "")
    
    echo "  Zone Label:        $zone_label"
    echo "  ProviderID Zone:  $provider_zone"
    echo "  Spec Zone:        $spec_zone"
    if [ -n "$subnet_filter" ]; then
        echo "  Subnet Filter:     $subnet_filter"
    fi
    
    # Check consistency
    if [ "$zone_label" != "N/A" ] && [ "$provider_zone" != "N/A" ] && [ "$spec_zone" != "N/A" ]; then
        if [ "$zone_label" = "$provider_zone" ] && [ "$provider_zone" = "$spec_zone" ]; then
            echo "  ✅ Zone consistent"
        else
            echo "  ❌ Zone inconsistent!"
            all_consistent=false
        fi
    else
        echo "  ⚠️  Warning: Some zone information is missing"
        if [ "$zone_label" != "$provider_zone" ] || [ "$provider_zone" != "$spec_zone" ]; then
            all_consistent=false
        fi
    fi
    echo ""
done

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""
echo "Checked $machine_count master machine(s)"
echo ""

if [ "$all_consistent" = true ]; then
    echo "✅ Verification PASSED: All machines have consistent zones!"
    echo ""
    echo "Cluster verification: PASS ✓"
    echo ""
    echo "Fix verification successful:"
    echo "  - Zone label, ProviderID zone, and Spec zone are all consistent"
    echo "  - Machines are created in the correct availability zones"
    exit 0
else
    echo "❌ Verification FAILED: Machines with inconsistent zones detected!"
    echo ""
    echo "Cluster verification: FAIL ✗"
    echo ""
    echo "Possible issues:"
    echo "  1. Fix not effective"
    echo "  2. Machines created in wrong availability zones"
    echo "  3. Zone label does not match actual zone"
    exit 1
fi
