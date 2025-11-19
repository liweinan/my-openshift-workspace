#!/bin/bash
set -e

WORK_DIR="/Users/weli/works/oc-swarm/openshift-versions/work"
SCRIPT_PATH="/Users/weli/works/oc-swarm/release/ci-operator/step-registry/cucushift/installer/check/reboot-nodes/cucushift-installer-check-reboot-nodes-commands.sh"

cd "$WORK_DIR"

# Set environment variables
export ENABLE_REBOOT_CHECK=true
export REBOOT_TYPE=HARD_REBOOT
export CLUSTER_TYPE=aws
export LEASED_RESOURCE=us-east-1
export SHARED_DIR="$WORK_DIR"
export CLUSTER_PROFILE_DIR="$WORK_DIR"

# Setup kubeconfig
if [ ! -f "$SHARED_DIR/kubeconfig" ] && [ -f "$SHARED_DIR/auth/kubeconfig" ]; then
    cp "$SHARED_DIR/auth/kubeconfig" "$SHARED_DIR/kubeconfig"
    echo "✓ Copied kubeconfig to SHARED_DIR"
fi

# Setup AWS credentials for local testing
# In CI environment, CLUSTER_PROFILE_DIR/.awscred is used
# For local testing, we use ~/.aws/credentials if available
if [ -f "$HOME/.aws/credentials" ]; then
    echo "✓ Found local AWS credentials at $HOME/.aws/credentials"
    # For local testing, copy real credentials to CLUSTER_PROFILE_DIR/.awscred
    # This simulates CI environment while using real credentials
    cp "$HOME/.aws/credentials" "$CLUSTER_PROFILE_DIR/.awscred"
    echo "✓ Copied local AWS credentials to CLUSTER_PROFILE_DIR/.awscred for testing"
    
    # Verify credentials format (CI expects simple key=value format)
    if grep -q "^aws_access_key_id" "$CLUSTER_PROFILE_DIR/.awscred" && grep -q "^aws_secret_access_key" "$CLUSTER_PROFILE_DIR/.awscred"; then
        echo "✓ Credentials file format looks correct"
    else
        # Convert from INI format to CI format if needed
        echo "Converting credentials from INI format to CI format..."
        AWS_ACCESS_KEY_ID=$(grep "^aws_access_key_id" "$HOME/.aws/credentials" | head -1 | sed 's/.*=\s*//' | tr -d ' ')
        AWS_SECRET_ACCESS_KEY=$(grep "^aws_secret_access_key" "$HOME/.aws/credentials" | head -1 | sed 's/.*=\s*//' | tr -d ' ')
        if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
            cat > "$CLUSTER_PROFILE_DIR/.awscred" << AWSCRED
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
AWSCRED
            echo "✓ Converted credentials to CI format"
        fi
    fi
else
    echo "⚠ Warning: No local AWS credentials found at $HOME/.aws/credentials"
    # Create dummy AWS credentials file if it doesn't exist
    if [ ! -f "$CLUSTER_PROFILE_DIR/.awscred" ]; then
        cat > "$CLUSTER_PROFILE_DIR/.awscred" << 'AWSCRED'
aws_access_key_id=test-key-id
aws_secret_access_key=test-secret-key
AWSCRED
        echo "✓ Created dummy .awscred file (will not work with real AWS)"
    fi
fi

# Create dummy SSH private key if it doesn't exist
if [ ! -f "$CLUSTER_PROFILE_DIR/ssh-privatekey" ]; then
    ssh-keygen -t rsa -b 2048 -f "$CLUSTER_PROFILE_DIR/ssh-privatekey" -N "" -C "test-key" > /dev/null 2>&1 || true
    echo "✓ Created dummy ssh-privatekey file"
fi

# Check if metadata.json exists
if [ ! -f "$SHARED_DIR/metadata.json" ]; then
    echo "❌ ERROR: metadata.json not found"
    exit 1
fi

# Extract INFRA_ID from metadata.json
INFRA_ID=$(jq -r '.infraID' "$SHARED_DIR/metadata.json" 2>/dev/null || echo "")
if [ -z "$INFRA_ID" ]; then
    echo "❌ ERROR: Could not extract infraID from metadata.json"
    exit 1
fi

echo ""
echo "Environment setup complete:"
echo "  SHARED_DIR: $SHARED_DIR"
echo "  CLUSTER_PROFILE_DIR: $CLUSTER_PROFILE_DIR"
echo "  REBOOT_TYPE: $REBOOT_TYPE"
echo "  CLUSTER_TYPE: $CLUSTER_TYPE"
echo "  LEASED_RESOURCE: $LEASED_RESOURCE"
echo "  INFRA_ID: $INFRA_ID"
echo ""

# Test AWS CLI access using the same credentials file format as CI
echo "Testing AWS CLI access..."
export AWS_REGION="$LEASED_RESOURCE"
export AWS_SHARED_CREDENTIALS_FILE="$CLUSTER_PROFILE_DIR/.awscred"

# Check if AWS CLI can use the credentials file
if aws sts get-caller-identity --region "$LEASED_RESOURCE" > /dev/null 2>&1; then
    echo "✓ AWS CLI authentication successful"
    AWS_ACCOUNT=$(aws sts get-caller-identity --region "$LEASED_RESOURCE" --query Account --output text 2>/dev/null || echo "unknown")
    echo "  AWS Account: $AWS_ACCOUNT"
    
    # Test finding instances
    echo ""
    echo "Testing instance lookup for INFRA_ID: $INFRA_ID"
    INSTANCE_COUNT=$(aws ec2 describe-instances \
        --region "$LEASED_RESOURCE" \
        --filters "Name=tag-key,Values=kubernetes.io/cluster/$INFRA_ID" \
                   "Name=instance-state-name,Values=running,stopped,pending,stopping" \
        --query 'length(Reservations[*].Instances[*].InstanceId)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$INSTANCE_COUNT" -gt 0 ]; then
        echo "✓ Found $INSTANCE_COUNT instance(s) for this cluster"
        INSTANCE_IDS=$(aws ec2 describe-instances \
            --region "$LEASED_RESOURCE" \
            --filters "Name=tag-key,Values=kubernetes.io/cluster/$INFRA_ID" \
                       "Name=instance-state-name,Values=running,stopped,pending,stopping" \
            --query 'Reservations[*].Instances[*].InstanceId' \
            --output text 2>/dev/null || echo "")
        echo "  Instance IDs: $INSTANCE_IDS"
    else
        echo "⚠ Warning: No instances found for INFRA_ID: $INFRA_ID"
        echo "  This could mean:"
        echo "    1. The cluster instances have been deleted"
        echo "    2. The INFRA_ID doesn't match AWS tags"
        echo "    3. The instances are in a different region"
    fi
else
    echo "⚠ Warning: AWS CLI authentication failed"
    echo "  Credentials file: $CLUSTER_PROFILE_DIR/.awscred"
    echo "  Check if the credentials file format is correct"
    echo ""
    echo "Expected format (CI format):"
    echo "  aws_access_key_id=AKIA..."
    echo "  aws_secret_access_key=..."
    echo ""
    echo "Current file content (first 3 lines):"
    head -3 "$CLUSTER_PROFILE_DIR/.awscred" 2>/dev/null || echo "  (file not found)"
fi

echo ""
echo "Running script: $SCRIPT_PATH"
echo "---"

# Run the script
bash "$SCRIPT_PATH"
