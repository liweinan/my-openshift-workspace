#!/bin/bash

# Verify zone allocation consistency in CAPI and MAPI manifests
# Usage: ./verify-manifests.sh <installation_directory>

set -e

INSTALL_DIR="${1:-.}"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: Directory does not exist: $INSTALL_DIR"
    echo "Usage: $0 <installation_directory>"
    exit 1
fi

echo "=========================================="
echo "Verify CAPI and MAPI Manifest Zone Consistency"
echo "=========================================="
echo ""
echo "Installation directory: $INSTALL_DIR"
echo ""

# Check required tools
if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq tool is required"
    echo "Install: brew install yq or visit https://github.com/mikefarah/yq"
    exit 1
fi

# Check if manifest files exist
CAPI_FILES=$(find "$INSTALL_DIR"/openshift -name "*cluster-api*master*.yaml" -type f 2>/dev/null | sort)
MAPI_FILES=$(find "$INSTALL_DIR"/openshift -name "*machine-api*master*.yaml" -type f 2>/dev/null | sort)

if [ -z "$CAPI_FILES" ]; then
    echo "❌ Error: CAPI manifest files not found"
    echo "   Please ensure you have run: openshift-install create manifests --dir=$INSTALL_DIR"
    exit 1
fi

if [ -z "$MAPI_FILES" ]; then
    echo "❌ Error: MAPI manifest files not found"
    echo "   Please ensure you have run: openshift-install create manifests --dir=$INSTALL_DIR"
    exit 1
fi

# Get CAPI zones
echo "CAPI Machine Zones:"
capi_zones=()
capi_index=0
for file in $CAPI_FILES; do
    # CAPI files are direct Machine objects, path is spec.providerSpec.value.placement.availabilityZone
    zone=$(yq eval '.spec.providerSpec.value.placement.availabilityZone' "$file" 2>/dev/null)
    if [ -n "$zone" ] && [ "$zone" != "null" ] && [ "$zone" != "" ]; then
        capi_zones+=("$zone")
        echo "  master-$capi_index ($(basename "$file")): $zone"
        capi_index=$((capi_index + 1))
    fi
done

if [ ${#capi_zones[@]} -eq 0 ]; then
    echo "  ⚠️  Warning: No CAPI zone information found"
    echo "    Attempted path: .spec.providerSpec.value.placement.availabilityZone"
    exit 1
fi

echo ""

# Get MAPI zones
echo "MAPI Machine Zones:"
mapi_zones=()

# MAPI files are ControlPlaneMachineSet, need to extract zones from failureDomains
for file in $MAPI_FILES; do
    # Check if it's a ControlPlaneMachineSet
    kind=$(yq eval '.kind' "$file" 2>/dev/null)
    if [ "$kind" = "ControlPlaneMachineSet" ]; then
        # Extract all zones from failureDomains (in order)
        zones=$(yq eval '.spec.template.machines_v1beta1_machine_openshift_io.failureDomains.aws[].placement.availabilityZone' "$file" 2>/dev/null)
        if [ -n "$zones" ]; then
            # Get master count (usually 3)
            master_count=${#capi_zones[@]}
            if [ $master_count -eq 0 ]; then
                master_count=3  # Default 3 masters
            fi
            
            # Extract first N zones in order (corresponding to master count)
            mapi_index=0
            for zone in $zones; do
                if [ "$zone" != "null" ] && [ -n "$zone" ] && [ "$zone" != "" ]; then
                    mapi_zones+=("$zone")
                    echo "  master-$mapi_index (from $(basename "$file")): $zone"
                    mapi_index=$((mapi_index + 1))
                    # Only take the same number of zones as CAPI
                    if [ $mapi_index -ge $master_count ]; then
                        break
                    fi
                fi
            done
        fi
    else
        # If it's a direct Machine object
        zone=$(yq eval '.spec.providerSpec.value.placement.availabilityZone' "$file" 2>/dev/null)
        if [ -n "$zone" ] && [ "$zone" != "null" ] && [ "$zone" != "" ]; then
            mapi_zones+=("$zone")
            echo "  master-${#mapi_zones[@]} ($(basename "$file")): $zone"
        fi
    fi
done

if [ ${#mapi_zones[@]} -eq 0 ]; then
    echo "  ⚠️  Warning: No MAPI zone information found"
    echo "    Attempted path: .spec.template.machines_v1beta1_machine_openshift_io.failureDomains.aws[].placement.availabilityZone"
    exit 1
fi

echo ""

# Compare
echo "=========================================="
echo "Consistency Check"
echo "=========================================="

if [ ${#capi_zones[@]} -ne ${#mapi_zones[@]} ]; then
    echo "⚠️  Warning: CAPI and MAPI have different number of machines"
    echo "   CAPI: ${#capi_zones[@]} machines"
    echo "   MAPI: ${#mapi_zones[@]} machines"
    echo ""
fi

all_match=true
max_count=${#capi_zones[@]}
if [ ${#mapi_zones[@]} -gt $max_count ]; then
    max_count=${#mapi_zones[@]}
fi

for i in $(seq 0 $((max_count - 1))); do
    capi_zone="${capi_zones[$i]:-N/A}"
    mapi_zone="${mapi_zones[$i]:-N/A}"
    
    if [ "$capi_zone" = "$mapi_zone" ] && [ "$capi_zone" != "N/A" ]; then
        echo "✓ Match: master-$i - Zone: $capi_zone"
    else
        echo "❌ Mismatch: master-$i - CAPI: $capi_zone, MAPI: $mapi_zone"
        all_match=false
    fi
done

echo ""

if [ "$all_match" = true ]; then
    echo "✅ Verification PASSED: All machines have consistent zone allocation!"
    echo ""
    echo "Manifest verification: PASS ✓"
    exit 0
else
    echo "❌ Verification FAILED: Zone allocation inconsistency detected!"
    echo ""
    echo "Manifest verification: FAIL ✗"
    exit 1
fi
