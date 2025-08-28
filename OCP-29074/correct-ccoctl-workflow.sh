#!/bin/bash

# Correct OpenShift 4.20 ccoctl workflow
# For OCP-29074: [ipi-on-aws] disable CCO and provide credentials manually

set -e

echo "=== Correct OpenShift 4.20 ccoctl workflow ==="
echo ""

# Configuration variables
CLUSTER_NAME="weli-test"
REGION="us-east-1"
PULL_SECRET_FILE="pull-secret.json"
RELEASE_IMAGE="registry.ci.openshift.org/ocp/release:4.20.0-0.nightly-2025-07-31-063120"

echo "📋 Workflow overview:"
echo "1. Create manifests and disable CCO"
echo "2. Extract CredentialsRequests"
echo "3. Use ccoctl to generate IAM users and policies"
echo "4. Install OpenShift cluster"
echo "5. Apply ccoctl-generated secrets (two methods available)"
echo ""

# Step 1: Check required files
echo "1. Checking required files..."
if [ ! -f "$PULL_SECRET_FILE" ]; then
    echo "❌ Error: $PULL_SECRET_FILE not found"
    exit 1
fi

if [ ! -f "install-config.yaml" ]; then
    echo "❌ Error: install-config.yaml not found"
    exit 1
fi

echo "✅ Required files check passed"
echo ""

# Step 2: Create manifests
echo "2. Creating manifests..."
if [ ! -d "manifests" ]; then
    echo "Executing: openshift-install create manifests --dir ."
    openshift-install create manifests --dir .
    echo "✅ Manifests created successfully"
else
    echo "✅ Manifests directory already exists"
fi
echo ""

# Step 3: Disable CCO
echo "3. Disabling Cloud Credential Operator..."
CCO_CONFIG="manifests/01_cloud-credential-operator-config.yaml"
if [ ! -f "$CCO_CONFIG" ]; then
    cat > "$CCO_CONFIG" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloud-credential-operator-config
  namespace: openshift-cloud-credential-operator
  annotations:
    release.openshift.io/create-only: "true"
data:
  disabled: "true"
EOF
    echo "✅ CCO disable config created: $CCO_CONFIG"
else
    echo "✅ CCO disable config already exists: $CCO_CONFIG"
fi
echo ""

# Step 4: Extract CredentialsRequests
echo "4. Extracting CredentialsRequests..."
RELEASE_IMAGE_DIR="./release-image"
if [ ! -d "$RELEASE_IMAGE_DIR" ]; then
    echo "Executing: oc adm release extract $RELEASE_IMAGE -a $PULL_SECRET_FILE --to $RELEASE_IMAGE_DIR"
    oc adm release extract "$RELEASE_IMAGE" -a "$PULL_SECRET_FILE" --to "$RELEASE_IMAGE_DIR"
    echo "✅ CredentialsRequests extracted successfully"
else
    echo "✅ release-image directory already exists"
fi
echo ""

# Step 5: Filter AWS CredentialsRequests
echo "5. Filtering AWS CredentialsRequests..."
AWS_CREDS_FILE="aws-credentials-requests.yaml"
if [ ! -f "$AWS_CREDS_FILE" ]; then
    echo "Executing: grep -l 'kind: AWSProviderSpec' $RELEASE_IMAGE_DIR/* | xargs cat > $AWS_CREDS_FILE"
    grep -l "kind: AWSProviderSpec" "$RELEASE_IMAGE_DIR"/* | xargs cat > "$AWS_CREDS_FILE"
    echo "✅ AWS CredentialsRequests saved to: $AWS_CREDS_FILE"
else
    echo "✅ AWS CredentialsRequests file already exists: $AWS_CREDS_FILE"
fi
echo ""

# Step 6: Check ccoctl tool
echo "6. Checking ccoctl tool..."
if ! command -v ccoctl &> /dev/null; then
    echo "❌ Error: ccoctl not installed"
    echo "Installation methods:"
    echo "  go install github.com/openshift/cloud-credential-operator/cmd/ccoctl@latest"
    exit 1
fi
echo "✅ ccoctl installed: $(ccoctl version)"
echo ""

# Step 7: Use ccoctl to create IAM users and policies
echo "7. Using ccoctl to create AWS IAM users and policies..."
CCOCTL_OUTPUT_DIR="./ccoctl-output"
if [ ! -d "$CCOCTL_OUTPUT_DIR" ]; then
    echo "Executing: ccoctl aws create-iam-users --name=$CLUSTER_NAME --region=$REGION --credentials-requests-dir=$AWS_CREDS_FILE --output-dir=$CCOCTL_OUTPUT_DIR"
    ccoctl aws create-iam-users \
        --name="$CLUSTER_NAME" \
        --region="$REGION" \
        --credentials-requests-dir="$AWS_CREDS_FILE" \
        --output-dir="$CCOCTL_OUTPUT_DIR"
    echo "✅ ccoctl execution completed"
else
    echo "✅ ccoctl output directory already exists: $CCOCTL_OUTPUT_DIR"
fi
echo ""

# Step 8: Show generated files
echo "8. ccoctl generated files:"
if [ -d "$CCOCTL_OUTPUT_DIR" ]; then
    if command -v tree &> /dev/null; then
        tree "$CCOCTL_OUTPUT_DIR"
    else
        echo "📁 $CCOCTL_OUTPUT_DIR/"
        find "$CCOCTL_OUTPUT_DIR" -type f | sed 's|^|   |'
    fi
fi
echo ""

# Step 9: Two methods to apply ccoctl-generated credentials
echo "9. 📋 Two methods to apply ccoctl-generated credentials:"
echo ""
echo "Method A: Apply after cluster installation (Recommended)"
echo "  - Keep ccoctl output in ccoctl-output/manifests/"
echo "  - Install cluster first"
echo "  - Apply credentials after cluster is ready"
echo ""
echo "Method B: Apply during cluster installation"
echo "  - Copy ccoctl-generated files to openshift/ directory"
echo "  - Rename files to match openshift-install naming convention"
echo "  - Install cluster (credentials applied automatically)"
echo ""
echo "Both methods are valid. Choose based on your preference:"
echo "  - Method A: More secure, follows ccoctl design principles"
echo "  - Method B: Smoother installation, no temporary degraded states"
echo ""

# Step 10: Start installation
echo "10. 🚀 Start OpenShift cluster installation..."
echo ""
echo "Choose your preferred method:"
echo ""
echo "Method A (Post-installation):"
echo "  openshift-install create cluster --dir . --log-level=info"
echo ""
echo "Method B (During installation):"
echo "  # First, copy and rename ccoctl files:"
echo "  cp ccoctl-output/manifests/* openshift/"
echo "  # Rename files to match openshift-install convention:"
echo "  # openshift-machine-api-aws-cloud-credentials-secret.yaml -> 99_openshift-machine-api_aws-cloud-credentials-secret.yaml"
echo "  # Then install:"
echo "  openshift-install create cluster --dir . --log-level=info"
echo ""
echo "Installation may take 30-60 minutes..."
echo ""

# Step 11: Post-installation operations
echo "11. 📋 Post-installation operations:"
echo ""
echo "After cluster is fully started:"
echo ""
echo "  # Set kubeconfig"
echo "  export KUBECONFIG=auth/kubeconfig"
echo ""
echo "  # Verify cluster status"
echo "  oc get clusteroperator"
echo ""
echo "Method A users:"
echo "  # Apply ccoctl-generated secrets"
echo "  oc apply -f $CCOCTL_OUTPUT_DIR/manifests/"
echo ""
echo "Method B users:"
echo "  # Secrets already applied during installation"
echo "  # Just verify they exist:"
echo "  oc get secret -A | grep cloud-credentials"
echo ""
echo "  # Verify all secrets are applied"
echo "  oc get secret -A | grep cloud-credentials"
echo ""

echo "=== Workflow completed ==="
echo ""
echo "📝 Summary:"
echo "- ccoctl generates the same secret content as manual creation"
echo "- Two methods available: post-installation or during installation"
echo "- Both methods are valid and produce identical results"
echo "- Choose based on your security and convenience preferences"
