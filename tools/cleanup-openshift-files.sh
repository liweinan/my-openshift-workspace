#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to safely remove files/directories
safe_remove() {
    local target="$1"
    local description="$2"
    
    if [ -e "${target}" ]; then
        if [ -d "${target}" ]; then
            echo "  Removing directory: ${target}"
            rm -rf "${target}"
        else
            echo "  Removing file: ${target}"
            rm -f "${target}"
        fi
        print_success "${description}"
    else
        echo "  Not found: ${target}"
    fi
}

# Function to find and remove files by pattern
remove_by_pattern() {
    local pattern="$1"
    local description="$2"
    local found_files=()
    
    # Find files matching pattern
    while IFS= read -r -d '' file; do
        found_files+=("$file")
    done < <(find "${WORKSPACE_ROOT}" -name "${pattern}" -type f -print0 2>/dev/null)
    
    if [ ${#found_files[@]} -gt 0 ]; then
        echo "  Found ${#found_files[@]} file(s) matching '${pattern}':"
        for file in "${found_files[@]}"; do
            echo "    - ${file}"
            rm -f "${file}"
        done
        print_success "${description}"
    else
        echo "  No files found matching '${pattern}'"
    fi
}

# Function to find and remove directories by pattern
remove_dirs_by_pattern() {
    local pattern="$1"
    local description="$2"
    local found_dirs=()
    
    # Find directories matching pattern
    while IFS= read -r -d '' dir; do
        found_dirs+=("$dir")
    done < <(find "${WORKSPACE_ROOT}" -name "${pattern}" -type d -print0 2>/dev/null)
    
    if [ ${#found_dirs[@]} -gt 0 ]; then
        echo "  Found ${#found_dirs[@]} directory(ies) matching '${pattern}':"
        for dir in "${found_dirs[@]}"; do
            echo "    - ${dir}"
            rm -rf "${dir}"
        done
        print_success "${description}"
    else
        echo "  No directories found matching '${pattern}'"
    fi
}

# --- Main Script ---
print_header "OpenShift Installation Files Cleanup"
echo "Workspace root: ${WORKSPACE_ROOT}"
echo ""

# Check if running in dry-run mode
DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    print_warning "Running in DRY-RUN mode - no files will be deleted"
    echo ""
fi

# Confirmation prompt
if [ "${DRY_RUN}" = false ]; then
    print_warning "This script will delete OpenShift installation files in the workspace."
    print_warning "This includes:"
    echo "  - All work*/ directories"
    echo "  - All .openshift_install* files"
    echo "  - All .clusterapi_output/ directories"
    echo "  - All auth/ directories"
    echo "  - All tls/ directories"
    echo "  - All metadata.json files"
    echo "  - All terraform files"
    echo "  - All log files"
    echo "  - All temporary files"
    echo ""
    print_info "OCP project directories will be preserved (contain useful scripts)"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Cleanup cancelled by user."
        exit 0
    fi
    echo ""
fi

# Override rm commands for dry-run
if [ "${DRY_RUN}" = true ]; then
    rm() {
        echo "  [DRY-RUN] Would remove: $*"
    }
fi

# --- Cleanup Operations ---

print_header "1. Cleaning OpenShift Installation Directories"
# Remove work directories
remove_dirs_by_pattern "work*" "Removed work directories"

print_header "2. Cleaning OpenShift Installer State Files"
# Remove .openshift_install files
remove_by_pattern ".openshift_install*" "Removed OpenShift installer state files"

print_header "3. Cleaning Cluster API Output Directories"
# Remove .clusterapi_output directories
remove_dirs_by_pattern ".clusterapi_output" "Removed Cluster API output directories"

print_header "4. Cleaning Authentication Files"
# Remove auth directories
remove_dirs_by_pattern "auth" "Removed authentication directories"

print_header "5. Cleaning TLS Certificates"
# Remove tls directories
remove_dirs_by_pattern "tls" "Removed TLS certificate directories"

print_header "6. Cleaning Metadata Files"
# Remove metadata.json files
remove_by_pattern "metadata.json" "Removed metadata files"

print_header "7. Cleaning Terraform Files"
# Remove terraform files
remove_by_pattern "terraform.tfstate*" "Removed Terraform state files"
remove_by_pattern "terraform.platform.auto.tfvars.json" "Removed Terraform auto tfvars files"
remove_by_pattern "terraform.tfvars.json" "Removed Terraform tfvars files"

print_header "8. Cleaning Log Files"
# Remove log files
remove_by_pattern "*.log" "Removed log files"

print_header "9. Cleaning Temporary Files"
# Remove temporary files
remove_by_pattern "*.tmp" "Removed temporary files"
remove_by_pattern "*.bak" "Removed backup files"
remove_by_pattern "*.swp" "Removed swap files"
remove_by_pattern "*~" "Removed tilde backup files"

print_header "10. Cleaning Installation Artifacts"
# Remove specific installation artifacts
remove_by_pattern "log-bundle-*.tar.gz" "Removed log bundle files"
remove_by_pattern "*.pem" "Removed PEM key files"

print_header "11. Preserving OCP Project Directories"
echo "  OCP project directories contain useful scripts and are preserved:"
OCP_DIRS=()
while IFS= read -r -d '' dir; do
    OCP_DIRS+=("$dir")
done < <(find "${WORKSPACE_ROOT}" -maxdepth 1 -name "OCP-*" -type d -print0 2>/dev/null)

if [ ${#OCP_DIRS[@]} -gt 0 ]; then
    for dir in "${OCP_DIRS[@]}"; do
        echo "    - $(basename "${dir}") (preserved)"
    done
    print_info "OCP project directories preserved (contain useful scripts)"
else
    echo "  No OCP project directories found"
fi

# --- Summary ---
print_header "Cleanup Summary"
if [ "${DRY_RUN}" = true ]; then
    print_info "Dry-run completed. No files were actually deleted."
    echo ""
    print_info "To perform actual cleanup, run:"
    echo "  $0"
else
    print_success "OpenShift installation files cleanup completed!"
fi

echo ""
print_info "Remaining files in workspace:"
echo "  - tools/ directory (utility scripts)"
echo "  - generate-metadata/ directory (metadata generation tools)"
echo "  - README files and documentation"
echo "  - Configuration templates and samples"

echo ""
print_info "If you need to clean up AWS resources as well, use:"
echo "  ./check-cluster-destroy-status.sh <installer-directory>"
echo "  ./delete-stacks-by-name.sh <stack-name-pattern>"
